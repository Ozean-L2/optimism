// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { console2 as console } from "forge-std/console2.sol";
import { CommonTest } from "test/setup/CommonTest.sol";
import { DeployConfig } from "scripts/DeployConfig.s.sol";
import { TestERC20, TestERC20Decimals } from "test/mocks/TestERC20.sol";

/// @dev forge test --match-contract USDXBridgeTest
contract USDXBridgeTest is CommonTest {
    TestERC20 public usdx;         /// 18 decimals
    TestERC20Decimals public usdc; /// 6 decimals
    TestERC20Decimals public usdt; /// 6 decimals
    TestERC20Decimals public dai;  /// 18 decimals

    function setUp() public override {
        /// @dev Mocks for each token
        /// USDX: 0x238ab60b0CC4588919fe25773202AA07675921dA
        usdx = new TestERC20{salt: bytes32("USDX")}();
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
        assertEq(
            usdx.allowance(address(usdxBridge), address(optimismPortal)),
            2**256 - 1
        );
        assertEq(usdxBridge.allowlisted(address(usdc)), true);
        assertEq(usdxBridge.allowlisted(address(usdt)), true);
        assertEq(usdxBridge.allowlisted(address(dai)), true);
    }

    /// @dev Deposit USDX directly via portal
    function testNativeGasDeposit() public prank(alice) {
        /// Mint 100 tokens
        usdx.mint(alice, 100e18);
        /// Grant approval to portal
        usdx.approve(address(optimismPortal), 100e18);
        /// Deposit
        optimismPortal.depositERC20Transaction({
            _to: alice,
            _mint: 100e18,
            _value: 100e18,
            _gasLimit: 1e6,
            _isCreation: false,
            _data: ""
        });
        assertEq(usdx.balanceOf(address(optimismPortal)), 100e18);
    }

    function testBridgeUSDX() public prank(alice) {
        /// Fund the bridge
        usdx.mint(alice, 100e18);
        usdx.transfer(address(usdxBridge), 100e18);

        /// Mint some USDC
        usdc.mint(alice, 100e6);
        /// Grant approval to bridge
        usdc.approve(address(usdxBridge), 100e6);
        /// Bridge
        usdxBridge.bridge(address(usdc), 100e6, alice);

        assertEq(usdx.balanceOf(address(optimismPortal)), 100e18);
        /// @dev Validate emision of events and other state update here also
    }
}
