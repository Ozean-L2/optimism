// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { console2 as console } from "forge-std/console2.sol";
import { CommonTest } from "test/setup/CommonTest.sol";
import { OzUSD } from "src/L2/OzUSD.sol";
import { OzUSDDeploy } from "scripts/ozean/OzUSDDeploy.s.sol";

/// @dev forge test --match-contract OzUSDTest -vvv
contract OzUSDTest is CommonTest {
    OzUSD public ozUSD;

    function setUp() public override {
        /// Deploy Ozean
        super.setUp();

        /// Deploy OzUSD
        OzUSDDeploy deployScript = new OzUSDDeploy();
        deployScript.run();
        ozUSD = deployScript.ozUSD();
    }

    /// SETUP ///

    function testInitialize() public view {
        assertEq(address(ozUSD).balance, 1e18);
    }

    function testRebase() public prank(alice) {
        uint256 sharesAmount = 1e18;
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);

        (bool s,) = address(ozUSD).call{ value: 1e18 }("");
        assert(s);

        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 2e18);
    }

    function testMintAndRebase() public prank(alice) {
        uint256 sharesAmount = 1e18;

        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);

        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);

        assertEq(address(ozUSD).balance, 2e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);

        (bool s,) = address(ozUSD).call{ value: 1e18 }("");
        assert(s);

        assertEq(address(ozUSD).balance, 3e18);
        assertEq(ozUSD.balanceOf(alice), 1.5e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1.5e18);
    }

    function testMintAndRedeem() public prank(alice) {
        uint256 sharesAmount = 1e18;

        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);

        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);

        assertEq(address(ozUSD).balance, 2e18);
        assertEq(ozUSD.balanceOf(alice), 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);

        ozUSD.approve(alice, 1e18);
        ozUSD.redeemOzUSD(alice, 1e18);

        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.balanceOf(alice), 0);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);
    }

    function testMintRebaseAndRedeem() public prank(alice) {
        uint256 sharesAmount = 1e18;

        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);

        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);

        assertEq(address(ozUSD).balance, 2e18);
        assertEq(ozUSD.balanceOf(alice), 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);

        (bool s,) = address(ozUSD).call{ value: 1e18 }("");
        assert(s);

        assertEq(address(ozUSD).balance, 3e18);
        assertEq(ozUSD.balanceOf(alice), 1.5e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1.5e18);

        ozUSD.approve(alice, 1.5e18);
        ozUSD.redeemOzUSD(alice, 1.5e18);

        assertEq(address(ozUSD).balance, 1.5e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1.5e18);
    }
}
