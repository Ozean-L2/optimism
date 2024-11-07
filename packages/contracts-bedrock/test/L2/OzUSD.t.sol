// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { console2 as console } from "forge-std/console2.sol";
import { CommonTest } from "test/setup/CommonTest.sol";
import { OzUSD } from "src/L2/OzUSD.sol";
import { OzUSDDeploy, TransparentUpgradeableProxy } from "scripts/ozean/OzUSDDeploy.s.sol";

/// @dev forge test --match-contract OzUSDTest -vvv
contract OzUSDTest is CommonTest {
    address public admin;
    OzUSD public implementation;
    OzUSD public ozUSD;

    event TransferShares(address indexed from, address indexed to, uint256 sharesValue);
    event SharesBurnt(address indexed account, uint256 preRebaseTokenAmount, uint256 postRebaseTokenAmount, uint256 sharesAmount);
    event YieldDistributed(uint256 _previousTotalBalance, uint256 _newTotalBalance);

    function setUp() public override {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        admin = makeAddr("admin");
        vm.deal(alice, 10000 ether);
        vm.deal(bob, 10000 ether);
        vm.deal(admin, 10000 ether);

        /// Deploy OzUSD
        OzUSDDeploy deployScript = new OzUSDDeploy();
        deployScript.run();
        implementation = deployScript.implementation();
        ozUSD = OzUSD(payable(deployScript.proxy()));
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

        vm.expectEmit(true, true, true, true);
        emit YieldDistributed(1e18, 1e18 + sharesAmount);
        ozUSD.distributeYield{value: sharesAmount}();

        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), (sharesAmount * address(ozUSD).balance) / 1e18);
    }

    function testMintAndRebase(uint256 _amountA, uint256 _amountB) public prank(alice) {
        _amountA = bound(_amountA, 1, 1e21);
        _amountB = bound(_amountB, 1, 1e21);

        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        ozUSD.mintOzUSD{ value: _amountA }(alice, _amountA);

        assertEq(address(ozUSD).balance, 1e18 + _amountA);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        vm.expectEmit(true, true, true, true);
        emit YieldDistributed(1e18 + _amountA, 1e18 + _amountA + _amountB);
        ozUSD.distributeYield{value: _amountB}();

        assertEq(address(ozUSD).balance, 1e18 + _amountA + _amountB);
        assertEq(ozUSD.balanceOf(alice), ozUSD.getPooledUSDXByShares(_amountA));
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), (_amountA * (1e18 + _amountA + _amountB)) / (1e18 + _amountA));
    }

    function testMintAndRedeem(uint256 _amountA) public prank(alice) {
        _amountA = bound(_amountA, 1, 1e21);

        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        ozUSD.mintOzUSD{ value: _amountA }(alice, _amountA);

        assertEq(address(ozUSD).balance, 1e18 + _amountA);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        ozUSD.approve(alice, _amountA);
        ozUSD.redeemOzUSD(alice, _amountA);

        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.balanceOf(alice), 0);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);
    }

    function testMintRebaseAndRedeem(uint256 _amountA, uint256 _amountB) public prank(alice) {
        _amountA = bound(_amountA, 1, 1e21);
        _amountB = bound(_amountB, 1, 1e21);

        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        ozUSD.mintOzUSD{ value: _amountA }(alice, _amountA);

        assertEq(address(ozUSD).balance, 1e18 + _amountA);
        assertEq(ozUSD.balanceOf(alice), _amountA);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        vm.expectEmit(true, true, true, true);
        emit YieldDistributed(1e18 + _amountA, 1e18 + _amountA + _amountB);
        ozUSD.distributeYield{value: _amountB}();

        uint256 predictedAliceAmount = (_amountA * (1e18 + _amountA + _amountB)) / (1e18 + _amountA);

        assertEq(address(ozUSD).balance, 1e18 + _amountA + _amountB);
        assertEq(ozUSD.balanceOf(alice), ozUSD.getPooledUSDXByShares(_amountA));
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), predictedAliceAmount);

        ozUSD.approve(alice, predictedAliceAmount);
        ozUSD.redeemOzUSD(alice, predictedAliceAmount);

        assertEq(address(ozUSD).balance, (1e18 + _amountA + _amountB) - predictedAliceAmount);
        /// @dev precision loss here
        ///assertEq(ozUSD.getPooledUSDXByShares(_amountA), predictedFinalAmount);
    }

    function testMintRebaseAndRedeem() public prank(alice) {
        uint256 sharesAmount = 1e18;

        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);

        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);

        assertEq(address(ozUSD).balance, 2e18);
        assertEq(ozUSD.balanceOf(alice), 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);

        vm.expectEmit(true, true, true, true);
        emit YieldDistributed(2e18, 3e18);
        ozUSD.distributeYield{value: 1e18}();

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

    /// PROXY ///

    /// @dev Can only be called by admin, otherwise delegatecalls to impl
    function testAdmin() public prank(admin) {
        assertEq(TransparentUpgradeableProxy(payable(ozUSD)).admin(), admin);
    }

    function testProxyInitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        implementation.initialize{ value: 1e18 }(1e18);

        assertEq(address(implementation).balance, 0);

        vm.expectRevert("Initializable: contract is already initialized");
        ozUSD.initialize{ value: 1e18 }(1e18);

        assertEq(address(ozUSD).balance, 1e18);
    }

    function testUpgradeImplementation() public prank(admin) {
        OzUSD newImplementation = new OzUSD();

        assertEq(TransparentUpgradeableProxy(payable(ozUSD)).implementation(), address(implementation));

        TransparentUpgradeableProxy(payable(ozUSD)).upgradeToAndCall(address(newImplementation), "");

        assertEq(TransparentUpgradeableProxy(payable(ozUSD)).implementation(), address(newImplementation));
    }
}
