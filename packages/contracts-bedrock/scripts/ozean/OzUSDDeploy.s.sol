// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { OzUSD } from "src/L2/OzUSD.sol";

contract OzUSDDeploy is Script {
    OzUSD public implementation;
    TransparentUpgradeableProxy public proxy;
    address public admin = makeAddr("admin");
    uint256 public initialSharesAmount = 1e18;

    function run() external broadcast {
        /// Deploy implementation
        implementation = new OzUSD();

        /// Deploy Proxy
        proxy = new TransparentUpgradeableProxy{ value: initialSharesAmount }(
            address(implementation), admin, abi.encodeCall(implementation.initialize, initialSharesAmount)
        );
    }

    modifier broadcast() {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }
}
