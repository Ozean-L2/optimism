// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { console2 as console } from "forge-std/console2.sol";
import { CommonTest } from "test/setup/CommonTest.sol";
import { OzUSD } from "src/L2/OzUSD.sol";
import { WozUSD } from "src/L2/WozUSD.sol";
import { OzUSDDeploy } from "scripts/ozean/OzUSDDeploy.s.sol";
import { WozUSDDeploy } from "scripts/ozean/WozUSDDeploy.s.sol";

/// @dev forge test --match-contract WozUSDTest -vvv
contract WozUSDTest is CommonTest {
    OzUSD public ozUSD;
    WozUSD public wozUSD;

    function setUp() public override {
        /// Deploy Ozean
        super.setUp();

        /// Deploy OzUSD
        OzUSDDeploy ozDeployScript = new OzUSDDeploy();
        ozDeployScript.run();
        ozUSD = ozDeployScript.ozUSD();

        /// Deploy WozUSD
        WozUSDDeploy wozDeployScript = new WozUSDDeploy();
        wozDeployScript.setUp(ozUSD);
        wozDeployScript.run();
        wozUSD = wozDeployScript.wozUSD();
    }

    /// SETUP ///

    function testInitialize() public view {
        assertEq(address(ozUSD).balance, 1e18);
        assertEq(wozUSD.totalSupply(), 0);
    }

    function testWrap() public prank(alice) {
        uint256 sharesAmount = 1e18;
        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);
        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);

        /// Wrap
        ozUSD.approve(address(wozUSD), ~uint256(0));
        wozUSD.wrap(1e18);

        assertEq(wozUSD.balanceOf(alice), sharesAmount);
    }

    function testUnWrap() public prank(alice) {
        uint256 sharesAmount = 1e18;
        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);
        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);

        /// Wrap
        ozUSD.approve(address(wozUSD), ~uint256(0));
        wozUSD.wrap(1e18);

        /// Unwrap
        wozUSD.unwrap(1e18);
    }

    function testWrapAndRebase() public prank(alice) {
        uint256 sharesAmount = 1e18;
        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);
        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);

        /// Wrap
        ozUSD.approve(address(wozUSD), ~uint256(0));
        wozUSD.wrap(1e18);

        (bool s,) = address(ozUSD).call{ value: 1e18 }("");
        assert(s);

        /// Unwrap
        wozUSD.unwrap(1e18);

        assertEq(ozUSD.balanceOf(alice), 1.5e18);
    }
}
