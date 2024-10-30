// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { console2 as console } from "forge-std/console2.sol";
import { CommonTest } from "test/setup/CommonTest.sol";
import { LGEStakingDeploy } from "scripts/ozean/LGEStakingDeploy.s.sol";
import { LGEStaking } from "src/L1/LGEStaking.sol";
import { TestERC20Decimals } from "test/mocks/TestERC20.sol";

/// @dev forge test --match-contract LGEStakingTest
contract LGEStakingTest is CommonTest {
    LGEStaking public lgeStaking;
    address public lgeMigration;
    address public hexTrust;

    /// 18 decimals
    TestERC20Decimals public wBTC;
    TestERC20Decimals public solvBTC;
    TestERC20Decimals public lombardBTC;
    TestERC20Decimals public wSOL;
    TestERC20Decimals public wstETH;
    TestERC20Decimals public sUSDe;
    TestERC20Decimals public USDe;
    TestERC20Decimals public AUSD;
    TestERC20Decimals public USDY;
    TestERC20Decimals public USDM;
    TestERC20Decimals public sDAI;
    /// 6 decimals
    TestERC20Decimals public USDC;

    address[] public tokens;
    uint256[] public depositCaps;

    /// LGEStaking events
    event Deposit(address indexed _token, uint256 _amount, address indexed _to);
    event Withdraw(address indexed _token, uint256 _amount, address indexed _to);
    event AllowlistSet(address indexed _coin, bool _set);
    event DepositCapSet(address indexed _coin, uint256 _newDepositCap);
    event TokensMigrated(address indexed _user, address indexed _l2Destination, address[] _tokens, uint256[] _amounts);
    event MigrationActivated(bool _set);
    event MigrationContractSet(address _newContract);

    function setUp() public override {
        /// Set up environment
        hexTrust = makeAddr("HEX_TRUST");
        wBTC = new TestERC20Decimals{ salt: bytes32("wBTC") }(18);
        solvBTC = new TestERC20Decimals{ salt: bytes32("solvBTC") }(18);
        lombardBTC = new TestERC20Decimals{ salt: bytes32("lombardBTC") }(18);
        wSOL = new TestERC20Decimals{ salt: bytes32("wSOL") }(18);
        wstETH = new TestERC20Decimals{ salt: bytes32("wstETH") }(18);
        sUSDe = new TestERC20Decimals{ salt: bytes32("sUSDe") }(18);
        USDe = new TestERC20Decimals{ salt: bytes32("USDe") }(18);
        AUSD = new TestERC20Decimals{ salt: bytes32("AUSD") }(18);
        USDY = new TestERC20Decimals{ salt: bytes32("USDY") }(18);
        USDM = new TestERC20Decimals{ salt: bytes32("USDM") }(18);
        sDAI = new TestERC20Decimals{ salt: bytes32("sDAI") }(18);
        USDC = new TestERC20Decimals{ salt: bytes32("USDC") }(6);

        /// Deploy Ozean
        super.setUp();

        /// Deploy LGEStaking
        tokens = new address[](13);
        tokens[0] = address(wBTC);
        tokens[1] = address(solvBTC);
        tokens[2] = address(lombardBTC);
        tokens[3] = address(wSOL);
        tokens[4] = address(wstETH);
        tokens[5] = address(sUSDe);
        tokens[6] = address(USDe);
        tokens[7] = address(AUSD);
        tokens[8] = address(USDY);
        tokens[9] = address(USDM);
        tokens[10] = address(sDAI);
        tokens[11] = address(USDC);
        tokens[12] = address(usdx);

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

        LGEStakingDeploy deployScript = new LGEStakingDeploy();
        deployScript.setUp(hexTrust, lgeMigration, tokens, depositCaps);
        deployScript.run();
        lgeStaking = deployScript.lgeStaking();
    }

    /// SETUP ///

    function testInitialize() public view {
        assertEq(lgeStaking.version(), "1.0.0");
        assertEq(address(lgeStaking.LGEMigration()), lgeMigration);
        assertEq(lgeStaking.migrationActivated(), false);

        for (uint256 i; i < 13; i++) {
            assertEq(lgeStaking.allowlisted(tokens[i]), true);
            assertEq(lgeStaking.depositCap(tokens[i]), 1e30);
            assertEq(lgeStaking.totalDeposited(tokens[i]), 0);
        }
    }

    /// DEPOSIT ///

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
        lgeStaking.setMigrationActivation(true);
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

    /// depositETH failure
    /// depositETH success

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

    /// MIGRATE ///

    /// migrate failure
    /// migrate success

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

    /// set paused
    /// set migration
    /// set migration contract
}
