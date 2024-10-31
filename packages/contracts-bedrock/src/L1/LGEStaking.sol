// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { ISemver } from "src/universal/ISemver.sol";
import { ILGEMigration } from "src/L1/interface/ILGEMigration.sol";

/// TODO Migration contract V1, tests, nat spec

/// @title  LGE Staking
/// @notice This contract ...
/// @dev    Inspired by https://vscode.blockscan.com/ethereum/0xf047ab4c75cebf0eb9ed34ae2c186f3611aeafa6
contract LGEStaking is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice The contract address for Lido's staked ether.
    address public immutable stETH;

    /// @notice The contract address for Lido's wrapped staked ether.
    /// @dev    All ETH deposits are converted to wstETH on deposit.
    address public immutable wstETH;

    /// @notice The migration contract that facilitates unstaking and deposits to the Ozean L2.
    ILGEMigration public LGEMigration;

    /// @notice A switch used to gate migration of deposited assets to the Ozean L2.
    bool public migrationActivated;

    /// @notice Addresses of allow-listed ERC20 tokens.
    /// @dev    token => allowlisted
    mapping(address => bool) public allowlisted;

    /// @notice The total amount of tokens deposted via this contract per allowlisted token address.
    /// @dev    token => amount
    mapping(address => uint256) public totalDeposited;

    /// @notice The limit to the amount that can be minted and bridged per token address.
    /// @dev    token => amount
    mapping(address => uint256) public depositCap;

    /// @notice The amount of tokens each user deposited for each allowlisted token.
    /// @dev    token => user => amount
    mapping(address => mapping(address => uint256)) public balance;

    /// EVENTS ///

    /// @notice An event emitted when a deposit is made by a user.
    event Deposit(address indexed _token, uint256 _amount, address indexed _to);

    /// @notice An event emitted when is withdrawal is made by a user.
    event Withdraw(address indexed _token, uint256 _amount, address indexed _to);

    /// @notice An event emitted when en ERC20 token is set as allowlisted or not (true if allowlisted, false if
    /// removed).
    event AllowlistSet(address indexed _coin, bool _set);

    /// @notice An event emitted when the deposit cap for an ERC20 token is modified.
    event DepositCapSet(address indexed _coin, uint256 _newDepositCap);

    /// @notice An event emitted when a user migrates deposited assets to Ozean.
    event TokensMigrated(address indexed _user, address indexed _l2Destination, address[] _tokens, uint256[] _amounts);

    /// @notice An event emitted when the migrationActivated boolean switch is modified.
    event MigrationActivated(bool _set);

    /// @notice An event emitted when the migration contract is modified.
    event MigrationContractSet(address _newContract);

    /// SETUP ///

    constructor(
        address _owner,
        address _lgeMigration,
        address _stETH,
        address _wstETH,
        address[] memory _tokens,
        uint256[] memory _depositCaps
    ) {
        _transferOwnership(_owner);
        LGEMigration = ILGEMigration(_lgeMigration);
        stETH = _stETH;
        wstETH = _wstETH;
        IstETH(stETH).approve(wstETH, ~uint256(0));
        uint256 length = _tokens.length;
        require(
            length == _depositCaps.length, "LGE Staking: Tokens array length must equal the Deposit Caps array length."
        );
        for (uint256 i; i < length; ++i) {
            allowlisted[_tokens[i]] = true;
            emit AllowlistSet(_tokens[i], true);
            depositCap[_tokens[i]] = _depositCaps[i];
            emit DepositCapSet(_tokens[i], _depositCaps[i]);
        }
    }

    /// DEPOSIT ///

    /// @dev Must grant approval for the contract to move tokens
    function depositERC20(address _token, uint256 _amount) external nonReentrant whenNotPaused {
        require(!migrationActivated, "LGE Staking: May not deposit once migration has been activated.");
        require(_amount > 0, "LGE Staking: May not deposit nothing.");
        require(allowlisted[_token], "LGE Staking: Token must be allowlisted.");
        require(
            totalDeposited[_token] + _amount < depositCap[_token], "LGE Staking: deposit amount exceeds deposit cap."
        );
        balance[_token][msg.sender] += _amount;
        totalDeposited[_token] += _amount;
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        emit Deposit(_token, _amount, msg.sender);
    }

    /// @dev All ETH is converted to wstETH
    function depositETH() external payable nonReentrant whenNotPaused {
        require(!migrationActivated, "LGE Staking: May not deposit once migration has been activated.");
        require(msg.value > 0, "LGE Staking: May not deposit nothing.");
        require(allowlisted[wstETH], "LGE Staking: Token must be allowlisted.");
        uint256 stETHAmount = IstETH(stETH).submit{ value: msg.value }(address(0));
        uint256 wstETHAmount = IwstETH(wstETH).wrap(stETHAmount);
        require(
            totalDeposited[wstETH] + wstETHAmount < depositCap[wstETH],
            "LGE Staking: deposit amount exceeds deposit cap."
        );
        balance[wstETH][msg.sender] += wstETHAmount;
        totalDeposited[wstETH] += wstETHAmount;
        emit Deposit(wstETH, wstETHAmount, msg.sender);
    }

    /// WITHDRAW ///

    function withdraw(address _token, uint256 _amount) external nonReentrant whenNotPaused {
        require(_amount > 0, "LGE Staking: may not withdraw nothing.");
        require(balance[_token][msg.sender] >= _amount, "LGE Staking: insufficient deposited balance.");
        balance[_token][msg.sender] -= _amount;
        totalDeposited[_token] -= _amount;
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit Withdraw(_token, _amount, msg.sender);
    }

    /// MIGRATE ///

    /// @dev Sends assets to migration contract, and then calls `migrate` to move the assets to Ozean
    function migrate(address _l2Destination, address[] calldata _tokens) external nonReentrant whenNotPaused {
        require(migrationActivated, "LGE Staking: Migration not active.");
        require(_l2Destination != address(0), "LGE Staking: May not send tokens to the zero address.");
        uint256 length = _tokens.length;
        require(length > 0, "LGE Staking: Must migrate some tokens.");
        uint256[] memory amounts = new uint256[](length);
        uint256 amount;
        for (uint256 i; i < length; i++) {
            amount = balance[_tokens[i]][msg.sender];
            require(amount > 0, "LGE Staking: No tokens to migrate.");
            amounts[i] = amount;
            IERC20(_tokens[i]).safeTransfer(address(LGEMigration), amount);
        }
        LGEMigration.migrate(msg.sender, _l2Destination, _tokens, amounts);
        emit TokensMigrated(msg.sender, _l2Destination, _tokens, amounts);
    }

    /// OWNER ///

    /// @notice This function allows the owner to either add or remove an allow-listed token for deposit.
    /// @param  _token The token address to add or remove.
    /// @param  _set A boolean for whether the token is allow-listed or not. True for allow-listed, false otherwise.
    function setAllowlist(address _token, bool _set) external onlyOwner {
        allowlisted[_token] = _set;
        emit AllowlistSet(_token, _set);
    }

    /// @notice This function allows the owner to modify the deposit cap for deposited tokens.
    /// @param  _token The token address to modify the deposit cap.
    /// @param  _newDepositCap The new deposit cap.
    function setDepositCap(address _token, uint256 _newDepositCap) external onlyOwner {
        depositCap[_token] = _newDepositCap;
        emit DepositCapSet(_token, _newDepositCap);
    }

    /// @notice This function allows the owner to pause or unpause this contract.
    /// @param  _set The boolean for whether the contract is to be paused or unpaused. True for paused, false otherwise.
    function setPaused(bool _set) external onlyOwner {
        _set ? _pause() : _unpause();
    }

    /// @notice This function allows the owner to set the migration boolean switch, which when true allows users to
    /// migrated
    ///         deposited assets to the Ozean L2.
    /// @param  _set The boolean for whether migration is activated. True is activated, false otherwise.
    /// @dev    Activating migration will disable new deposits.
    function setMigrationActivation(bool _set) external onlyOwner {
        migrationActivated = _set;
        emit MigrationActivated(_set);
    }

    /// @notice This function allows the owner to set the migration contract used to move deposited assets to the
    ///         Ozean L2.
    /// @param  _contract The new contract address for the LGE Migration logic.
    /// @dev    The new migration contract must conform to the ILGEMigration interface.
    function setMigrationContract(address _contract) external onlyOwner {
        LGEMigration = ILGEMigration(_contract);
        emit MigrationContractSet(_contract);
    }
}

interface IstETH is IERC20 {
    function submit(address _referral) external payable returns (uint256);
}

interface IwstETH is IERC20 {
    function wrap(uint256 _stETHAmount) external returns (uint256);
}
