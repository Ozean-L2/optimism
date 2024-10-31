// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { LGEStaking } from "src/L1/LGEStaking.sol";

contract LGEStakingDeploy is Script {
    LGEStaking public lgeStaking;
    address public lgeMigration;
    address public stETH;
    address public wstETH;
    address public hexTrust = makeAddr("HEX_TRUST");
    address[] public tokens;
    uint256[] public depositCaps;

    /// @dev Used in testing environment, unnecessary for mainnet deployment
    function setUp(
        address _hexTrust,
        address _lgeMigration,
        address _stETH,
        address _wstETH,
        address[] memory _tokens,
        uint256[] memory _depositCaps
    )
        external
    {
        hexTrust = _hexTrust;
        lgeMigration = _lgeMigration;
        stETH = _stETH;
        wstETH = _wstETH;
        tokens = _tokens;
        depositCaps = _depositCaps;
    }

    function run() external broadcast {
        lgeStaking = new LGEStaking(hexTrust, lgeMigration, stETH, wstETH, tokens, depositCaps);
    }

    modifier broadcast() {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }
}
