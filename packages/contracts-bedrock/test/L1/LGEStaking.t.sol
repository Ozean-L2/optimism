// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { console2 as console } from "forge-std/console2.sol";
import { CommonTest } from "test/setup/CommonTest.sol";
import { LGEStakingDeploy } from "scripts/ozean/LGEStakingDeploy.s.sol";
import { LGEMigrationDeploy } from "scripts/ozean/LGEMigrationDeploy.s.sol";
import { LGEStaking } from "src/L1/LGEStaking.sol";
import { LGEMigrationV1 } from "src/L1/LGEMigrationV1.sol";
import { TestERC20Decimals } from "test/mocks/TestERC20.sol";
import { TestStETH, TestWstETH } from "test/mocks/TestLido.sol";

/// @dev forge test --match-contract LGEStakingTest
contract LGEStakingTest is CommonTest {
    LGEStaking public lgeStaking;
    LGEMigrationV1 public lgeMigration;
    address public hexTrust;

    /// 18 decimals
    TestERC20Decimals public wBTC;
    TestERC20Decimals public solvBTC;
    TestERC20Decimals public lombardBTC;
    TestERC20Decimals public wSOL;
    TestERC20Decimals public sUSDe;
    TestERC20Decimals public USDe;
    TestERC20Decimals public AUSD;
    TestERC20Decimals public USDY;
    TestERC20Decimals public USDM;
    TestERC20Decimals public sDAI;
    /// 6 decimals
    TestERC20Decimals public USDC;

    /// Mock Lido contracts
    TestStETH public stETH;
    TestWstETH public wstETH;
    
    /// @dev mock these too?
    address public l1LidoTokensBridge;
    address public usdxBridge;

    address[] public l1Addresses;
    address[] public l2Addresses;
    uint256[] public depositCaps;

    /// LGEStaking events
    event Deposit(address indexed _token, uint256 _amount, address indexed _to);
    event Withdraw(address indexed _token, uint256 _amount, address indexed _to);
    event AllowlistSet(address indexed _coin, bool _set);
    event DepositCapSet(address indexed _coin, uint256 _newDepositCap);
    event TokensMigrated(address indexed _user, address indexed _l2Destination, address[] _tokens, uint256[] _amounts);
    event MigrationContractSet(address _newContract);
    /// Pausable events
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public override {
        /// Set up environment
        /// @dev Hex Trust treated as owner of both lgeStaking and lgeMigration
        hexTrust = makeAddr("HEX_TRUST");
        wBTC = new TestERC20Decimals{ salt: bytes32("wBTC") }(18);
        solvBTC = new TestERC20Decimals{ salt: bytes32("solvBTC") }(18);
        lombardBTC = new TestERC20Decimals{ salt: bytes32("lombardBTC") }(18);
        wSOL = new TestERC20Decimals{ salt: bytes32("wSOL") }(18);
        sUSDe = new TestERC20Decimals{ salt: bytes32("sUSDe") }(18);
        USDe = new TestERC20Decimals{ salt: bytes32("USDe") }(18);
        AUSD = new TestERC20Decimals{ salt: bytes32("AUSD") }(18);
        USDY = new TestERC20Decimals{ salt: bytes32("USDY") }(18);
        USDM = new TestERC20Decimals{ salt: bytes32("USDM") }(18);
        sDAI = new TestERC20Decimals{ salt: bytes32("sDAI") }(18);
        USDC = new TestERC20Decimals{ salt: bytes32("USDC") }(6);
        stETH = new TestStETH();
        wstETH = new TestWstETH(address(stETH));

        /// Deploy Ozean
        super.setUp();

        /// Deploy LGEStaking
        l1Addresses = new address[](13);
        l1Addresses[0] = address(wBTC);
        l1Addresses[1] = address(solvBTC);
        l1Addresses[2] = address(lombardBTC);
        l1Addresses[3] = address(wSOL);
        l1Addresses[4] = address(wstETH);
        l1Addresses[5] = address(sUSDe);
        l1Addresses[6] = address(USDe);
        l1Addresses[7] = address(AUSD);
        l1Addresses[8] = address(USDY);
        l1Addresses[9] = address(USDM);
        l1Addresses[10] = address(sDAI);
        l1Addresses[11] = address(USDC);
        l1Addresses[12] = address(usdx);

        depositCaps = new uint256[](13);
        depositCaps[0] = 1e30;
        depositCaps[1] = 1e30;
        depositCaps[2] = 1e30;
        depositCaps[3] = 1e30;
        depositCaps[4] = 1e30;
        depositCaps[5] = 1e30;
        depositCaps[6] = 1e30;
        depositCaps[7] = 1e30;
        depositCaps[8] = 1e30;
        depositCaps[9] = 1e30;
        depositCaps[10] = 1e30;
        depositCaps[11] = 1e30;
        depositCaps[12] = 1e30;

        LGEStakingDeploy stakingDeployScript = new LGEStakingDeploy();
        stakingDeployScript.setUp(hexTrust, address(stETH), address(wstETH), l1Addresses, depositCaps);
        stakingDeployScript.run();
        lgeStaking = stakingDeployScript.lgeStaking();

        /// Deploy LGEMigration
        /// @dev not the correct L2 address
        l2Addresses = new address[](13);
        l2Addresses[0] = address(wBTC);

        LGEMigrationDeploy migrationDeployScript = new LGEMigrationDeploy();
        migrationDeployScript.setUp(
            address(l1StandardBridge),
            address(l1LidoTokensBridge),
            address(usdxBridge),
            address(lgeStaking),
            address(USDC),
            address(wstETH),
            l1Addresses,
            l2Addresses
        );
        migrationDeployScript.run();
        lgeMigration = migrationDeployScript.lgeMigration();
    }

    /// SETUP ///

    function testInitialize() public view {
        assertEq(lgeStaking.version(), "1.0.0");
        assertEq(address(lgeStaking.lgeMigration()), address(0));
        assertEq(lgeStaking.migrationActivated(), false);

        for (uint256 i; i < 13; i++) {
            assertEq(lgeStaking.allowlisted(l1Addresses[i]), true);
            assertEq(lgeStaking.depositCap(l1Addresses[i]), 1e30);
            assertEq(lgeStaking.totalDeposited(l1Addresses[i]), 0);
        }
    }

    function testDeployRevertWithUnequalArrayLengths() public {
        l1Addresses = new address[](3);
        l1Addresses[0] = address(wBTC);
        l1Addresses[1] = address(solvBTC);
        l1Addresses[2] = address(lombardBTC);
        depositCaps = new uint256[](2);
        depositCaps[0] = 1e30;
        depositCaps[1] = 1e30;
        vm.expectRevert("LGE Staking: Tokens array length must equal the Deposit Caps array length.");
        lgeStaking = new LGEStaking(hexTrust, address(stETH), address(wstETH), l1Addresses, depositCaps);

        /// LGE Migration
        vm.expectRevert("LGE Migration: L1 addresses array length must equal the L2 addresses array length.");
        lgeMigration = new LGEMigrationV1(
            address(l1StandardBridge),
            address(l1LidoTokensBridge),
            address(usdxBridge),
            address(lgeStaking),
            address(USDC),
            address(wstETH),
            l1Addresses,
            l2Addresses
        );
    }

    /// DEPOSIT ERC20 ///

    function testDepositERC20FailureConditions() public prank(alice) {
        wBTC.mint(alice, 1e31);

        /// Amount zero
        vm.expectRevert("LGE Staking: May not deposit nothing.");
        lgeStaking.depositERC20(address(wBTC), 0);

        /// Not allowlisted
        vm.expectRevert("LGE Staking: Token must be allowlisted.");
        lgeStaking.depositERC20(address(88), 1);

        /// Exceeding deposit caps
        vm.expectRevert("LGE Staking: deposit amount exceeds deposit cap.");
        lgeStaking.depositERC20(address(wBTC), 1e31);

        /// Migration activated
        vm.stopPrank();
        vm.startPrank(hexTrust);
        lgeStaking.setMigrationContract(address(lgeMigration));
        assertEq(lgeStaking.migrationActivated(), true);
        vm.stopPrank();
        vm.startPrank(alice);

        vm.expectRevert("LGE Staking: May not deposit once migration has been activated.");
        lgeStaking.depositERC20(address(wBTC), 1);
    }

    function testDepositERC20SuccessConditions(uint256 _amount) public prank(alice) {
        _amount = bound(_amount, 1, 1e30 - 1);
        wBTC.mint(alice, 1e31);
        wBTC.approve(address(lgeStaking), _amount);

        assertEq(lgeStaking.balance(address(wBTC), alice), 0);
        assertEq(lgeStaking.totalDeposited(address(wBTC)), 0);
        assertEq(wBTC.balanceOf(address(lgeStaking)), 0);

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(wBTC), _amount, alice);
        lgeStaking.depositERC20(address(wBTC), _amount);

        assertEq(lgeStaking.balance(address(wBTC), alice), _amount);
        assertEq(lgeStaking.totalDeposited(address(wBTC)), _amount);
        assertEq(wBTC.balanceOf(address(lgeStaking)), _amount);
    }

    /// DEPOSIT ETH ///

    function testDepositETHFailureConditions() public prank(hexTrust) {
        vm.deal(hexTrust, 10000 ether);

        /// Amount zero
        vm.expectRevert("LGE Staking: May not deposit nothing.");
        lgeStaking.depositETH{ value: 0 }();

        /// Migration activated
        lgeStaking.setMigrationContract(address(lgeMigration));
        assertEq(lgeStaking.migrationActivated(), true);
        vm.expectRevert("LGE Staking: May not deposit once migration has been activated.");
        lgeStaking.depositETH{ value: 1 ether }();

        lgeStaking.setMigrationContract(address(0));

        /// Not allowlisted
        lgeStaking.setAllowlist(address(wstETH), false);
        vm.expectRevert("LGE Staking: Token must be allowlisted.");
        lgeStaking.depositETH{ value: 1 ether }();

        lgeStaking.setAllowlist(address(wstETH), true);

        /// Exceeding deposit caps
        lgeStaking.setDepositCap(address(wstETH), 1 ether);
        vm.expectRevert("LGE Staking: deposit amount exceeds deposit cap.");
        lgeStaking.depositETH{ value: 10 ether }();
    }

    function testDepositETHSuccessConditions(uint256 _amount) public prank(alice) {
        _amount = bound(_amount, 1, 1e30 - 1);
        vm.deal(alice, 1e31);

        assertEq(lgeStaking.balance(address(wstETH), alice), 0);
        assertEq(lgeStaking.totalDeposited(address(wstETH)), 0);
        assertEq(wstETH.balanceOf(address(lgeStaking)), 0);

        uint256 predictedWSTETHAmount = wstETH.getWstETHByStETH(_amount);

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(wstETH), predictedWSTETHAmount, alice);
        lgeStaking.depositETH{ value: _amount }();

        assertEq(lgeStaking.balance(address(wstETH), alice), predictedWSTETHAmount);
        assertEq(lgeStaking.totalDeposited(address(wstETH)), predictedWSTETHAmount);
        assertEq(wstETH.balanceOf(address(lgeStaking)), predictedWSTETHAmount);
    }

    /// WITHDRAW ///

    function testWithdrawFailureConditions(uint256 _amount) public prank(alice) {
        /// Setup
        _amount = bound(_amount, 1, 1e30 - 1);
        wBTC.mint(alice, 1e31);
        wBTC.approve(address(lgeStaking), _amount);
        lgeStaking.depositERC20(address(wBTC), _amount);

        /// Amount zero
        vm.expectRevert("LGE Staking: may not withdraw nothing.");
        lgeStaking.withdraw(address(wBTC), 0);

        /// Insufficient balance
        vm.expectRevert("LGE Staking: insufficient deposited balance.");
        lgeStaking.withdraw(address(wBTC), _amount + 1);
    }

    function testWithdrawSuccessConditions(uint256 _amount0, uint256 _amount1) public prank(alice) {
        /// Setup
        _amount0 = bound(_amount0, 2, 1e30 - 1);
        _amount1 = bound(_amount1, 1, _amount0);
        wBTC.mint(alice, 1e31);
        wBTC.approve(address(lgeStaking), _amount0);
        lgeStaking.depositERC20(address(wBTC), _amount0);

        assertEq(lgeStaking.balance(address(wBTC), alice), _amount0);
        assertEq(lgeStaking.totalDeposited(address(wBTC)), _amount0);
        assertEq(wBTC.balanceOf(address(lgeStaking)), _amount0);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(wBTC), _amount1, alice);
        lgeStaking.withdraw(address(wBTC), _amount1);

        assertEq(lgeStaking.balance(address(wBTC), alice), _amount0 - _amount1);
        assertEq(lgeStaking.totalDeposited(address(wBTC)), _amount0 - _amount1);
        assertEq(wBTC.balanceOf(address(lgeStaking)), _amount0 - _amount1);
    }

    function testDepositETHAndWithdrawSuccessConditions(uint256 _amount0, uint256 _amount1) public prank(alice) {
        /// Setup
        _amount0 = bound(_amount0, 2, 1e30 - 1);
        uint256 predictedWSTETHAmount = wstETH.getWstETHByStETH(_amount0);
        _amount1 = bound(_amount1, 1, predictedWSTETHAmount);
        vm.deal(alice, 1e31);

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(wstETH), predictedWSTETHAmount, alice);
        lgeStaking.depositETH{ value: _amount0 }();

        assertEq(lgeStaking.balance(address(wstETH), alice), predictedWSTETHAmount);
        assertEq(lgeStaking.totalDeposited(address(wstETH)), predictedWSTETHAmount);
        assertEq(wstETH.balanceOf(address(lgeStaking)), predictedWSTETHAmount);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(wstETH), _amount1, alice);
        lgeStaking.withdraw(address(wstETH), _amount1);

        assertEq(lgeStaking.balance(address(wstETH), alice), predictedWSTETHAmount - _amount1);
        assertEq(lgeStaking.totalDeposited(address(wstETH)), predictedWSTETHAmount - _amount1);
        assertEq(wstETH.balanceOf(address(lgeStaking)), predictedWSTETHAmount - _amount1);
    }

    /// MIGRATE ///

    function testMigrateFailureConditions(uint256 _amount0) public prank(alice) {
        /// Setup
        _amount0 = bound(_amount0, 2, 1e30 - 1);

        wBTC.mint(alice, 1e31);
        wBTC.approve(address(lgeStaking), _amount0);
        lgeStaking.depositERC20(address(wBTC), _amount0);

        assertEq(lgeStaking.balance(address(wBTC), alice), _amount0);
        assertEq(lgeStaking.totalDeposited(address(wBTC)), _amount0);
        assertEq(wBTC.balanceOf(address(lgeStaking)), _amount0);

        USDC.mint(alice, 1e31);
        USDC.approve(address(lgeStaking), _amount0);
        lgeStaking.depositERC20(address(USDC), _amount0);

        assertEq(lgeStaking.balance(address(USDC), alice), _amount0);
        assertEq(lgeStaking.totalDeposited(address(USDC)), _amount0);
        assertEq(USDC.balanceOf(address(lgeStaking)), _amount0);

        /// Only LGE may call
        vm.expectRevert("LGE Migration: Only the staking contract can call this function.");
        lgeMigration.migrate(alice, l1Addresses, depositCaps);

        address[] memory tokens = new address[](1);
        tokens[0] = address(wBTC);

        /// Migration not active
        vm.expectRevert("LGE Staking: Migration not active.");
        lgeStaking.migrate(alice, tokens);

        /// L2 Destination zero address
        vm.stopPrank();
        vm.startPrank(hexTrust);
        lgeStaking.setMigrationContract(address(lgeMigration));
        assertEq(lgeStaking.migrationActivated(), true);
        vm.stopPrank();
        vm.startPrank(alice);

        vm.expectRevert("LGE Staking: May not send tokens to the zero address.");
        lgeStaking.migrate(address(0), tokens);

        /// Tokens length zero
        tokens = new address[](0);

        vm.expectRevert("LGE Staking: Must migrate some tokens.");
        lgeStaking.migrate(alice, tokens);

        /// No deposits to migrate
        tokens = new address[](1);
        tokens[0] = address(wSOL);

        vm.expectRevert("LGE Staking: No tokens to migrate.");
        lgeStaking.migrate(alice, tokens);

        /// L2 Address not set
        tokens[0] = address(USDC);

        vm.expectRevert("LGE Migration: L2 contract address not set for migration.");
        lgeStaking.migrate(alice, tokens);
    }

    function testMigrateSuccessConditions(uint256 _amount0) public prank(alice) {
        /// Setup
        _amount0 = bound(_amount0, 2, 1e30 - 1);
        wBTC.mint(alice, 1e31);
        wBTC.approve(address(lgeStaking), _amount0);
        lgeStaking.depositERC20(address(wBTC), _amount0);

        assertEq(lgeStaking.balance(address(wBTC), alice), _amount0);
        assertEq(lgeStaking.totalDeposited(address(wBTC)), _amount0);
        assertEq(wBTC.balanceOf(address(lgeStaking)), _amount0);

        /// Migrate
        vm.stopPrank();
        vm.startPrank(hexTrust);
        lgeStaking.setMigrationContract(address(lgeMigration));
        assertEq(lgeStaking.migrationActivated(), true);
        vm.stopPrank();
        vm.startPrank(alice);

        address[] memory tokens = new address[](1);
        tokens[0] = address(wBTC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _amount0;

        vm.expectEmit(true, true, true, true);
        emit TokensMigrated(alice, alice, tokens, amounts);
        lgeStaking.migrate(alice, tokens);

        assertEq(lgeStaking.balance(address(wBTC), alice), 0);
        assertEq(lgeStaking.totalDeposited(address(wBTC)), 0);
        assertEq(wBTC.balanceOf(address(lgeStaking)), 0);

        /// @dev Flesh this out a bit more
    }

    /// OWNER ///

    function testSetAllowlist() public {
        TestERC20Decimals USDD = new TestERC20Decimals(18);

        /// Non-owner revert
        vm.expectRevert("Ownable: caller is not the owner");
        lgeStaking.setAllowlist(address(USDD), true);

        /// Owner allowed to set new coin
        vm.startPrank(hexTrust);

        /// Add USDD
        vm.expectEmit(true, true, true, true);
        emit AllowlistSet(address(USDD), true);
        lgeStaking.setAllowlist(address(USDD), true);

        /// Remove USDC
        vm.expectEmit(true, true, true, true);
        emit AllowlistSet(address(USDC), false);
        lgeStaking.setAllowlist(address(USDC), false);

        vm.stopPrank();

        assertEq(lgeStaking.allowlisted(address(USDD)), true);
        assertEq(lgeStaking.allowlisted(address(USDC)), false);
    }

    function testSetDepositCap(uint256 _newCap) public {
        /// Non-owner revert
        vm.expectRevert("Ownable: caller is not the owner");
        lgeStaking.setDepositCap(address(USDC), _newCap);

        assertEq(lgeStaking.depositCap(address(USDC)), 1e30);

        /// Owner allowed
        vm.startPrank(hexTrust);

        vm.expectEmit(true, true, true, true);
        emit DepositCapSet(address(USDC), _newCap);
        lgeStaking.setDepositCap(address(USDC), _newCap);

        vm.stopPrank();

        assertEq(lgeStaking.depositCap(address(USDC)), _newCap);
    }

    function testSetPaused() public {
        vm.deal(hexTrust, 10000 ether);

        /// Non-owner revert
        vm.expectRevert("Ownable: caller is not the owner");
        lgeStaking.setPaused(true);

        assertEq(lgeStaking.paused(), false);

        /// Owner allowed
        vm.startPrank(hexTrust);

        vm.expectEmit(true, true, true, true);
        emit Paused(hexTrust);
        lgeStaking.setPaused(true);

        assertEq(lgeStaking.paused(), true);

        /// External functions paused
        vm.expectRevert("Pausable: paused");
        lgeStaking.depositERC20(address(wBTC), 1e18);

        vm.expectRevert("Pausable: paused");
        lgeStaking.depositETH{ value: 1e18 }();

        vm.expectRevert("Pausable: paused");
        lgeStaking.withdraw(address(wBTC), 1e18);

        address[] memory tokensArray;
        vm.expectRevert("Pausable: paused");
        lgeStaking.migrate(alice, tokensArray);

        vm.expectEmit(true, true, true, true);
        emit Unpaused(hexTrust);
        lgeStaking.setPaused(false);

        assertEq(lgeStaking.paused(), false);

        vm.stopPrank();
    }

    function testSetMigrationContract() public {
        address newMigrationContract = address(88);

        /// Non-owner revert
        vm.expectRevert("Ownable: caller is not the owner");
        lgeStaking.setMigrationContract(newMigrationContract);

        assertEq(address(lgeStaking.lgeMigration()), address(0));
        assertEq(lgeStaking.migrationActivated(), false);

        vm.startPrank(hexTrust);

        vm.expectEmit(true, true, true, true);
        emit MigrationContractSet(newMigrationContract);
        lgeStaking.setMigrationContract(newMigrationContract);

        assertEq(address(lgeStaking.lgeMigration()), newMigrationContract);
        assertEq(lgeStaking.migrationActivated(), true);

        vm.stopPrank();
    }
}
