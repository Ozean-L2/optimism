// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { OzUSD } from "src/L2/OzUSD.sol";

contract OzUSDDeploy is Script {
    OzUSD public ozUSD;

    uint256 public initialSharesAmount = 1e18;

    function run() external broadcast {
        ozUSD = new OzUSD{ value: initialSharesAmount }(initialSharesAmount);
    }

    modifier broadcast() {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }
}
