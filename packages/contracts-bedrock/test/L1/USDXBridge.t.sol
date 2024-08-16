// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { console2 as console } from "forge-std/console2.sol";
import { CommonTest } from "test/setup/CommonTest.sol";
import { DeployConfig } from "scripts/DeployConfig.s.sol";
import { MockUSDX } from "test/mocks/MockUSDX.sol";
import { TestERC20Decimals } from "test/mocks/TestERC20.sol";
import { AddressAliasHelper } from "src/vendor/AddressAliasHelper.sol";

/// @dev forge test --match-contract USDXBridgeTest
contract USDXBridgeTest is CommonTest {
    MockUSDX public usdx;          /// 18 decimals
    TestERC20Decimals public usdc; /// 6 decimals
    TestERC20Decimals public usdt; /// 6 decimals
    TestERC20Decimals public dai;  /// 18 decimals

    function setUp() public override {
        /// @dev Mocks for each token
        /// USDX: 0x640CB39e2D33Aa48EEE9AEC539420aF7Da72be8d
        usdx = new MockUSDX{salt: bytes32("USDX")}();
        /// USDC: 0xE9d6759D9e3218f8066B07D0cEcAd42AE4717B24
        usdc = new TestERC20Decimals{salt: bytes32("USDC")}(6);
        /// USDT: 0xb9Fa9c1d11a7cA88aE2EC18Cefbade6066809338
        usdt = new TestERC20Decimals{salt: bytes32("USDT")}(6);
        /// DAI:  0xB4E61Ba802BD1797e19D6f69492794bCECBDa95A
        dai = new TestERC20Decimals{salt: bytes32("DAI")}(18);
        super.setUp();
    }

    function testInitialize() public view {
        /// Environment
        (address addr, uint8 decimals) = systemConfig.gasPayingToken();
        assertEq(addr, address(usdx));
        assertEq(decimals, 18);

        /// Bridge
        assertEq(usdxBridge.owner(), deploy.cfg().finalSystemOwner());
        assertEq(address(usdxBridge.usdx()), address(usdx));
        assertEq(address(usdxBridge.portal()), address(optimismPortal));
        assertEq(address(usdxBridge.config()), address(systemConfig));
        assertEq(usdxBridge.depositCap(), 1e30);
        assertEq(usdxBridge.totalBridged(), 0);
        assertEq(usdx.allowance(address(usdxBridge), address(optimismPortal)), 0);
        assertEq(usdxBridge.allowlisted(address(usdc)), true);
        assertEq(usdxBridge.allowlisted(address(usdt)), true);
        assertEq(usdxBridge.allowlisted(address(dai)), true);
    }

    /// @dev Deposit USDX directly via portal, bypassing usdx bridge
    function testNativeGasDeposit(uint256 _amount) public prank(alice) {
        _amount = bound(_amount, 1, 100_000e18);

        /// Mint and approve
        usdx.mint(alice, _amount);
        usdx.approve(address(optimismPortal), _amount);

        /// Bridge directly
        vm.expectEmit(true, true, true, true);
        emit TransactionDeposited(
            AddressAliasHelper.applyL1ToL2Alias(alice),
            alice,
            0,
            _getOpaqueData(_amount, _amount, 21000, false, "")
        );
        optimismPortal.depositERC20Transaction({
            _to: alice,
            _mint: _amount,
            _value: _amount,
            _gasLimit: 21000,
            _isCreation: false,
            _data: ""
        });

        assertEq(usdx.balanceOf(address(optimismPortal)), _amount);
    }

    /// BRIDGE STABLECOINS ///

    function testBridgeUSDXRevertConditions(uint256 _amount) public prank(alice) {
        _amount = bound(_amount, 1, 100_000e18);

        /// Non-accepted stablecoin/ERC20
        TestERC20Decimals usde = new TestERC20Decimals(18);
        vm.expectRevert("USDXBridge: Stablecoin not accepted.");
        usdxBridge.bridge(address(usde), _amount, alice);

        /// Deposit zero
        vm.expectRevert("USDXBridge: May not bridge nothing.");
        usdxBridge.bridge(address(dai), 0, alice);

        /// Deposit Cap exceeded
        uint256 excess = usdxBridge.depositCap() + 1;
        vm.expectRevert("USDXBridge: Bridge amount exceeds deposit cap.");
        usdxBridge.bridge(address(dai), excess, alice);
    }

    function testBridgeUSDXWithUSDC(uint256 _amount) public prank(alice) {
        _amount = bound(_amount, 1, 100_000e6);

        /// Mint and approve
        usdc.mint(alice, _amount);
        usdc.approve(address(usdxBridge), _amount);
        uint256 usdxAmount = _amount * (10 ** 12);

        /// Bridge
        vm.expectEmit(true, true, true, true);
        emit TransactionDeposited(
            AddressAliasHelper.applyL1ToL2Alias(address(usdxBridge)),
            alice,
            0,
            _getOpaqueData(usdxAmount, usdxAmount, 21000, false, "")
        );
        usdxBridge.bridge(address(usdc), _amount, alice);

        assertEq(usdx.balanceOf(address(optimismPortal)), usdxAmount);
        assertEq(usdxBridge.totalBridged(), usdxAmount);
        assertEq(usdx.allowance(address(usdxBridge), address(optimismPortal)), 0);
    }

    function testBridgeUSDXWithUSDT(uint256 _amount) public prank(alice) {
        _amount = bound(_amount, 1, 100_000e6);

        /// Mint and approve
        usdt.mint(alice, _amount);
        usdt.approve(address(usdxBridge), _amount);
        uint256 usdxAmount = _amount * (10 ** 12);

        /// Bridge
        vm.expectEmit(true, true, true, true);
        emit TransactionDeposited(
            AddressAliasHelper.applyL1ToL2Alias(address(usdxBridge)),
            alice,
            0,
            _getOpaqueData(usdxAmount, usdxAmount, 21000, false, "")
        );
        usdxBridge.bridge(address(usdt), _amount, alice);

        assertEq(usdx.balanceOf(address(optimismPortal)), usdxAmount);
        assertEq(usdxBridge.totalBridged(), usdxAmount);
        assertEq(usdx.allowance(address(usdxBridge), address(optimismPortal)), 0);
    }

    function testBridgeUSDXWithDAI(uint256 _amount) public prank(alice) {
        _amount = bound(_amount, 1, 100_000e18);

        /// Mint and approve
        dai.mint(alice, _amount);
        dai.approve(address(usdxBridge), _amount);

        /// Bridge
        vm.expectEmit(true, true, true, true);
        emit TransactionDeposited(
            AddressAliasHelper.applyL1ToL2Alias(address(usdxBridge)),
            alice,
            0,
            _getOpaqueData(_amount, _amount, 21000, false, "")
        );
        usdxBridge.bridge(address(dai), _amount, alice);

        assertEq(usdx.balanceOf(address(optimismPortal)), _amount);
        assertEq(usdxBridge.totalBridged(), _amount);
        assertEq(usdx.allowance(address(usdxBridge), address(optimismPortal)), 0);
    }

    function testBridgeUSDXWithStablecoinWithOddDecimals(uint256 _amount, uint8 _decimals) public prank(alice) {
        _decimals = uint8(bound(_decimals, 0, 24));
        _amount = bound(_amount, 1, 100_000 * (10 ** _decimals));

        /// Create, mint, and approve
        TestERC20Decimals usde = new TestERC20Decimals(_decimals);
        usde.mint(alice, _amount);
        usde.approve(address(usdxBridge), _amount);

        uint256 usdxAmount;
        if (_decimals <= 18) {
            usdxAmount = _amount * (10 ** (18 - _decimals));
        } else {
            usdxAmount = _amount / (10 ** (_decimals - 18));
        }

        /// Owner adds stablecoin to allowlist
        vm.stopPrank();
        address owner = deploy.cfg().finalSystemOwner();
        vm.startPrank(owner);
        usdxBridge.setAllowlist(address(usde), true);
        vm.stopPrank();
        vm.startPrank(alice);

        /// Bridge
        vm.expectEmit(true, true, true, true);
        emit TransactionDeposited(
            AddressAliasHelper.applyL1ToL2Alias(address(usdxBridge)),
            alice,
            0,
            _getOpaqueData(usdxAmount, usdxAmount, 21000, false, "")
        );
        usdxBridge.bridge(address(usde), _amount, alice);

        assertEq(usdx.balanceOf(address(optimismPortal)), usdxAmount);
        assertEq(usdxBridge.totalBridged(), usdxAmount);
    }

    /// OWNER ///

    function testSetAllowlist() public {
        TestERC20Decimals usde = new TestERC20Decimals(18);

        /// Non-owner revert
        vm.expectRevert("Ownable: caller is not the owner");
        usdxBridge.setAllowlist(address(usde), true);

        /// Owner allowed to set new coin
        address owner = deploy.cfg().finalSystemOwner();
        vm.startPrank(owner);

        /// Add USDE
        usdxBridge.setAllowlist(address(usde), true);
        /// Remove DAI
        usdxBridge.setAllowlist(address(dai), false);

        vm.stopPrank();

        assertEq(usdxBridge.allowlisted(address(usde)), true);
        assertEq(usdxBridge.allowlisted(address(dai)), false);
    }

    function testSetDepositCap(uint256 _newCap) public {
        /// Non-owner revert
        vm.expectRevert("Ownable: caller is not the owner");
        usdxBridge.setDepositCap(_newCap);

        assertEq(usdxBridge.depositCap(), 1e30);

        /// Owner allowed
        address owner = deploy.cfg().finalSystemOwner();
        vm.startPrank(owner);

        usdxBridge.setDepositCap(_newCap);

        vm.stopPrank();

        assertEq(usdxBridge.depositCap(), _newCap);
    }

    function testWithdrawERC20(uint256 _amount) public {
        /// Send some tokens directly to the contract
        dai.mint(address(usdxBridge), _amount);

        assertEq(dai.balanceOf(address(usdxBridge)), _amount);

        /// Non-owner revert
        vm.expectRevert("Ownable: caller is not the owner");
        usdxBridge.withdrawERC20(address(dai), _amount);

        /// Owner allowed
        address owner = deploy.cfg().finalSystemOwner();
        vm.startPrank(owner);

        usdxBridge.withdrawERC20(address(dai), _amount);

        vm.stopPrank();

        assertEq(dai.balanceOf(address(usdxBridge)), 0);
        assertEq(dai.balanceOf(owner), _amount);
    }

    function testBridgeUSDXWithUSDCAndWithdraw(uint256 _amount) public prank(alice) {
        _amount = bound(_amount, 1, 100_000e6);

        /// Alice mints and approves
        usdc.mint(alice, _amount);
        usdc.approve(address(usdxBridge), _amount);
        uint256 usdxAmount = _amount * (10 ** 12);

        /// Alice bridges
        vm.expectEmit(true, true, true, true);
        emit TransactionDeposited(
            AddressAliasHelper.applyL1ToL2Alias(address(usdxBridge)),
            alice,
            0,
            _getOpaqueData(usdxAmount, usdxAmount, 21000, false, "")
        );
        usdxBridge.bridge(address(usdc), _amount, alice);

        assertEq(usdx.balanceOf(address(optimismPortal)), usdxAmount);
        assertEq(usdxBridge.totalBridged(), usdxAmount);

        /// Owner withdraws deposited USDC
        vm.stopPrank();
        address owner = deploy.cfg().finalSystemOwner();
        vm.startPrank(owner);

        usdxBridge.withdrawERC20(address(usdc), _amount);

        assertEq(usdc.balanceOf(address(usdxBridge)), 0);
        assertEq(usdc.balanceOf(owner), _amount);
    }

    /// HELPERS ///

    function _getOpaqueData(
        uint256 _mint,
        uint256 _value,
        uint64 _gasLimit,
        bool _isCreation,
        bytes memory _data
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(_mint, _value, _gasLimit, _isCreation, _data);
    }
}
