// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { OptimismPortal } from "src/L1/OptimismPortal.sol";
import { SystemConfig } from "src/L1/SystemConfig.sol";
import { USDXBridge } from "src/L1/USDXBridge.sol";
import "forge-std/console.sol";

contract USDXBridgeDeploy is Script {
    USDXBridge public usdxBridge;
    address public hexTrust;
    address public usdc;
    address public usdt;
    address public dai;
    OptimismPortal public optimismPortal;
    SystemConfig public systemConfig;

    /// @dev Used in testing environment, unnecessary for mainnet deployment
    function setUp(
        address _hexTrust,
        address _usdc,
        address _usdt,
        address _dai,
        OptimismPortal _optimismPortal,
        SystemConfig _systemConfig
    ) external {
        hexTrust = _hexTrust;
        usdc = _usdc;
        usdt = _usdt;
        dai = _dai;
        optimismPortal = _optimismPortal;
        systemConfig = _systemConfig;
    }

    function run() external broadcast {
        address[] memory stablecoins = new address[](3);
        stablecoins[0] = usdc;
        stablecoins[1] = usdt;
        stablecoins[2] = dai;
        uint256[] memory depositCaps = new uint256[](3);
        depositCaps[0] = 1e30;
        depositCaps[1] = 1e30;
        depositCaps[2] = 1e30;

        require(hexTrust != address(0), "Script: Zero address.");
        require(address(optimismPortal) != address(0), "Script: Zero address.");
        require(address(systemConfig) != address(0), "Script: Zero address.");

        uint256 length = stablecoins.length;
        require(length == depositCaps.length, "Script: Unequal length.");
        for (uint256 i; i < length; i++) {
            require(stablecoins[i] != address(0), "Script: Zero address.");
        }

        bytes memory deployData = abi.encode(hexTrust, optimismPortal, systemConfig, stablecoins, depositCaps);
        console.logBytes(deployData);

        usdxBridge = new USDXBridge(hexTrust, optimismPortal, systemConfig, stablecoins, depositCaps);
    }

    modifier broadcast() {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }
}