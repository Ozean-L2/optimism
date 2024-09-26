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
        assertEq(ozUSD.totalSupply(), 1e18);
        assertEq(ozUSD.name(), "Ozean USD");
        assertEq(ozUSD.symbol(), "ozUSD");
        assertEq(ozUSD.decimals(), 18);
    }

    /// REBASE ///

    function testRebase(uint256 sharesAmount) public prank(alice) {
        sharesAmount = bound(sharesAmount, 1, 1e20);
        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), sharesAmount);

        (bool s,) = address(ozUSD).call{ value: sharesAmount }("");
        assert(s);

        assertEq(
            ozUSD.getPooledUSDXByShares(sharesAmount), (sharesAmount * address(ozUSD).balance) / 1e18
        );
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

    /// ERC20 ///

    function testApproveAndTransferFrom() public prank(alice) {
        uint256 sharesAmount = 1e18;

        // Ensure initial balance
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);

        // Mint ozUSD
        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);

        assertEq(ozUSD.balanceOf(alice), 1e18);

        // Approve bob to spend alice's ozUSD
        ozUSD.approve(bob, 0.5e18);
        assertEq(ozUSD.allowance(alice, bob), 0.5e18);

        // Bob transfers 0.5e18 ozUSD from alice to charlie
        address charlie = address(77);
        vm.stopPrank();
        vm.prank(bob);
        ozUSD.transferFrom(alice, charlie, 0.5e18);

        assertEq(ozUSD.balanceOf(alice), 0.5e18);
        assertEq(ozUSD.balanceOf(charlie), 0.5e18);
        assertEq(ozUSD.allowance(alice, bob), 0); // Full amount transferred
    }

    function testIncreaseAndDecreaseAllowance() public prank(alice) {
        // Mint ozUSD
        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);
        assertEq(ozUSD.balanceOf(alice), 1e18);

        // Increase bob's allowance
        ozUSD.increaseAllowance(bob, 0.5e18);
        assertEq(ozUSD.allowance(alice, bob), 0.5e18);

        // Decrease bob's allowance
        ozUSD.decreaseAllowance(bob, 0.2e18);
        assertEq(ozUSD.allowance(alice, bob), 0.3e18);
    }

    function testTransferShares() public prank(alice) {
        // Mint ozUSD
        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);

        // Transfer shares from alice to bob
        uint256 sharesToTransfer = 0.5e18;
        uint256 tokensTransferred = ozUSD.transferShares(bob, sharesToTransfer);

        // Check balances after the transfer
        assertEq(ozUSD.balanceOf(alice), 0.5e18);
        assertEq(ozUSD.balanceOf(bob), tokensTransferred);
    }

    function testTransferMoreThanBalanceReverts() public prank(alice) {
        // Mint ozUSD
        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);

        // Attempt to transfer more than alice's balance
        vm.expectRevert("OzUSD: BALANCE_EXCEEDED");
        ozUSD.transfer(bob, 2e18); // Transfer amount exceeds balance
    }

    function testBurnShares() public prank(alice) {
        uint256 sharesAmount = 1e18;

        // Mint ozUSD
        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);
        assertEq(ozUSD.balanceOf(alice), 1e18);

        // Burn half of the shares
        ozUSD.approve(alice, 0.5e18);
        ozUSD.redeemOzUSD(alice, 0.5e18);

        // Check balances after burning
        assertEq(ozUSD.balanceOf(alice), 0.5e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);
    }

    function testAllowanceExceeded() public prank(alice) {
        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);

        // Alice approves Bob to spend 0.5 ozUSD
        ozUSD.approve(bob, 5e17);
        assertEq(ozUSD.allowance(alice, bob), 5e17);

        // Bob tries to transfer more than allowed, should fail
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert("OzUSD: ALLOWANCE_EXCEEDED");
        ozUSD.transferFrom(alice, bob, 1e18);
    }
}
