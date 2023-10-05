package cannon

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/ethereum-optimism/optimism/op-bindings/bindings"
	"github.com/ethereum-optimism/optimism/op-challenger/config"
	"github.com/ethereum-optimism/optimism/op-challenger/game/fault/types"
	"github.com/ethereum-optimism/optimism/op-service/ioutil"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/ethereum/go-ethereum/log"

	"github.com/ethereum-optimism/optimism/cannon/mipsevm"
)

const (
	proofsDir      = "proofs"
	diskStateCache = "state.bin.gz"
)

type proofData struct {
	ClaimValue   common.Hash   `json:"post"`
	StateData    hexutil.Bytes `json:"state-data"`
	ProofData    hexutil.Bytes `json:"proof-data"`
	OracleKey    hexutil.Bytes `json:"oracle-key,omitempty"`
	OracleValue  hexutil.Bytes `json:"oracle-value,omitempty"`
	OracleOffset uint32        `json:"oracle-offset,omitempty"`
}

type CannonMetricer interface {
	RecordCannonExecutionTime(t float64)
}

type ProofGenerator interface {
	// GenerateProof executes cannon to generate a proof at the specified trace index in dataDir.
	GenerateProof(ctx context.Context, dataDir string, proofAt uint64) error
}

type CannonTraceProvider struct {
	logger    log.Logger
	dir       string
	prestate  string
	generator ProofGenerator
	gameDepth uint64

	// lastStep stores the last step in the actual trace if known. 0 indicates unknown.
	// Cached as an optimisation to avoid repeatedly attempting to execute beyond the end of the trace.
	lastStep uint64
}

func NewTraceProvider(ctx context.Context, logger log.Logger, m CannonMetricer, cfg *config.Config, l1Client bind.ContractCaller, dir string, gameAddr common.Address, gameDepth uint64) (*CannonTraceProvider, error) {
	l2Client, err := ethclient.DialContext(ctx, cfg.CannonL2)
	if err != nil {
		return nil, fmt.Errorf("dial l2 client %v: %w", cfg.CannonL2, err)
	}
	defer l2Client.Close() // Not needed after fetching the inputs
	gameCaller, err := bindings.NewFaultDisputeGameCaller(gameAddr, l1Client)
	if err != nil {
		return nil, fmt.Errorf("create caller for game %v: %w", gameAddr, err)
	}
	localInputs, err := fetchLocalInputs(ctx, gameAddr, gameCaller, l2Client)
	if err != nil {
		return nil, fmt.Errorf("fetch local game inputs: %w", err)
	}
	return NewTraceProviderFromInputs(logger, m, cfg, localInputs, dir, gameDepth), nil
}

func NewTraceProviderFromInputs(logger log.Logger, m CannonMetricer, cfg *config.Config, localInputs LocalGameInputs, dir string, gameDepth uint64) *CannonTraceProvider {
	return &CannonTraceProvider{
		logger:    logger,
		dir:       dir,
		prestate:  cfg.CannonAbsolutePreState,
		generator: NewExecutor(logger, m, cfg, localInputs),
		gameDepth: gameDepth,
	}
}

func (p *CannonTraceProvider) SetMaxDepth(gameDepth uint64) {
	p.gameDepth = gameDepth
}

func (p *CannonTraceProvider) Get(ctx context.Context, pos types.Position) (common.Hash, error) {
	traceIndex := pos.TraceIndex(int(p.gameDepth))
	if !traceIndex.IsUint64() {
		return common.Hash{}, errors.New("trace index out of bounds")
	}
	proof, err := p.loadProof(ctx, traceIndex.Uint64())
	if err != nil {
		return common.Hash{}, err
	}
	value := proof.ClaimValue

	if value == (common.Hash{}) {
		return common.Hash{}, errors.New("proof missing post hash")
	}
	return value, nil
}

func (p *CannonTraceProvider) GetStepData(ctx context.Context, pos types.Position) ([]byte, []byte, *types.PreimageOracleData, error) {
	traceIndex := pos.TraceIndex(int(p.gameDepth))
	if !traceIndex.IsUint64() {
		return nil, nil, nil, errors.New("trace index out of bounds")
	}
	proof, err := p.loadProof(ctx, traceIndex.Uint64())
	if err != nil {
		return nil, nil, nil, err
	}
	value := ([]byte)(proof.StateData)
	if len(value) == 0 {
		return nil, nil, nil, errors.New("proof missing state data")
	}
	data := ([]byte)(proof.ProofData)
	if data == nil {
		return nil, nil, nil, errors.New("proof missing proof data")
	}
	var oracleData *types.PreimageOracleData
	if len(proof.OracleKey) > 0 {
		// TODO(client-pod#104): Replace the LocalContext `0` argument below with the correct local context.
		oracleData = types.NewPreimageOracleData(0, proof.OracleKey, proof.OracleValue, proof.OracleOffset)
	}
	return value, data, oracleData, nil
}

func (p *CannonTraceProvider) AbsolutePreState(ctx context.Context) ([]byte, error) {
	state, err := parseState(p.prestate)
	if err != nil {
		return nil, fmt.Errorf("cannot load absolute pre-state: %w", err)
	}
	return state.EncodeWitness(), nil
}

func (p *CannonTraceProvider) AbsolutePreStateCommitment(ctx context.Context) (common.Hash, error) {
	state, err := p.AbsolutePreState(ctx)
	if err != nil {
		return common.Hash{}, fmt.Errorf("cannot load absolute pre-state: %w", err)
	}
	hash, err := mipsevm.StateWitness(state).StateHash()
	if err != nil {
		return common.Hash{}, fmt.Errorf("cannot hash absolute pre-state: %w", err)
	}
	return hash, nil
}

// loadProof will attempt to load or generate the proof data at the specified index
// If the requested index is beyond the end of the actual trace it is extended with no-op instructions.
func (p *CannonTraceProvider) loadProof(ctx context.Context, i uint64) (*proofData, error) {
	// Attempt to read the last step from disk cache
	if p.lastStep == 0 {
		step, err := readLastStep(p.dir)
		if err != nil {
			p.logger.Warn("Failed to read last step from disk cache", "err", err)
		} else {
			p.lastStep = step
		}
	}
	// If the last step is tracked, set i to the last step to generate or load the final proof
	if p.lastStep != 0 && i > p.lastStep {
		i = p.lastStep
	}
	path := filepath.Join(p.dir, proofsDir, fmt.Sprintf("%d.json.gz", i))
	file, err := ioutil.OpenDecompressed(path)
	if errors.Is(err, os.ErrNotExist) {
		if err := p.generator.GenerateProof(ctx, p.dir, i); err != nil {
			return nil, fmt.Errorf("generate cannon trace with proof at %v: %w", i, err)
		}
		// Try opening the file again now and it should exist.
		file, err = ioutil.OpenDecompressed(path)
		if errors.Is(err, os.ErrNotExist) {
			// Expected proof wasn't generated, check if we reached the end of execution
			state, err := parseState(filepath.Join(p.dir, finalState))
			if err != nil {
				return nil, fmt.Errorf("cannot read final state: %w", err)
			}
			if state.Exited && state.Step <= i {
				p.logger.Warn("Requested proof was after the program exited", "proof", i, "last", state.Step)
				// The final instruction has already been applied to this state, so the last step we can execute
				// is one before its Step value.
				p.lastStep = state.Step - 1
				// Extend the trace out to the full length using a no-op instruction that doesn't change any state
				// No execution is done, so no proof-data or oracle values are required.
				witness := state.EncodeWitness()
				witnessHash, err := mipsevm.StateWitness(witness).StateHash()
				if err != nil {
					return nil, fmt.Errorf("cannot hash witness: %w", err)
				}
				proof := &proofData{
					ClaimValue:   witnessHash,
					StateData:    hexutil.Bytes(witness),
					ProofData:    []byte{},
					OracleKey:    nil,
					OracleValue:  nil,
					OracleOffset: 0,
				}
				if err := writeLastStep(p.dir, proof, p.lastStep); err != nil {
					p.logger.Warn("Failed to write last step to disk cache", "step", p.lastStep)
				}
				return proof, nil
			} else {
				return nil, fmt.Errorf("expected proof not generated but final state was not exited, requested step %v, final state at step %v", i, state.Step)
			}
		}
	}
	if err != nil {
		return nil, fmt.Errorf("cannot open proof file (%v): %w", path, err)
	}
	defer file.Close()
	var proof proofData
	err = json.NewDecoder(file).Decode(&proof)
	if err != nil {
		return nil, fmt.Errorf("failed to read proof (%v): %w", path, err)
	}
	return &proof, nil
}

type diskStateCacheObj struct {
	Step uint64 `json:"step"`
}

// readLastStep reads the tracked last step from disk.
func readLastStep(dir string) (uint64, error) {
	state := diskStateCacheObj{}
	file, err := ioutil.OpenDecompressed(filepath.Join(dir, diskStateCache))
	if err != nil {
		return 0, err
	}
	defer file.Close()
	err = json.NewDecoder(file).Decode(&state)
	if err != nil {
		return 0, err
	}
	return state.Step, nil
}

// writeLastStep writes the last step and proof to disk as a persistent cache.
func writeLastStep(dir string, proof *proofData, step uint64) error {
	state := diskStateCacheObj{Step: step}
	lastStepFile := filepath.Join(dir, diskStateCache)
	if err := ioutil.WriteCompressedJson(lastStepFile, state); err != nil {
		return fmt.Errorf("failed to write last step to %v: %w", lastStepFile, err)
	}
	if err := ioutil.WriteCompressedJson(filepath.Join(dir, proofsDir, fmt.Sprintf("%d.json.gz", step)), proof); err != nil {
		return fmt.Errorf("failed to write proof: %w", err)
	}
	return nil
}
