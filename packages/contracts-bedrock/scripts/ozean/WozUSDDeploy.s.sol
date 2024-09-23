// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { OzUSD } from "src/L2/OzUSD.sol";
import { WozUSD } from "src/L2/WozUSD.sol";

contract WozUSDDeploy is Script {
    OzUSD public ozUSD;
    WozUSD public wozUSD;

    uint256 public initialSharesAmount = 1e18;

    function setUp(OzUSD _ozUSD) external {
        ozUSD = _ozUSD;
    }

    function run() external broadcast {
        wozUSD = new WozUSD(ozUSD);
    }

    modifier broadcast() {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }
}
