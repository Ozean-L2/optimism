// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { OzUSD } from "src/L2/OzUSD.sol";
import { WozUSD } from "src/L2/WozUSD.sol";

contract OzUSDPackage is Script {
    address public admin = 0xa2ef4A5fB028b4543700AC83e87a0B8b4572202e;
    uint256 public initialSharesAmount = 1e18;

    function run() external broadcast {
        /// Deploy implementation
        OzUSD implementation = new OzUSD();

        /// Deploy Proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy{ value: initialSharesAmount }(
            address(implementation), admin, abi.encodeWithSignature("initialize(uint256)", initialSharesAmount)
        );

        /// Deploy wozUSD
        WozUSD wozUSD = new WozUSD(OzUSD(payable(proxy)));
        wozUSD;
    }

    modifier broadcast() {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }
}
