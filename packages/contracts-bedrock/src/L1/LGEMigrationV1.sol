// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { ILGEMigration } from "src/L1/interface/ILGEMigration.sol";

contract LGEMigrationV1 is ILGEMigration, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable lgeStaking;

    constructor(address _lgeStaking) {
        lgeStaking = _lgeStaking;
    }

    function migrate(
        address _user,
        address _l2Destination,
        address[] calldata _tokens,
        uint256[] calldata _amounts
    )
        external
        nonReentrant
    {
        require(msg.sender == lgeStaking, "LGE Migration: Only the staking contract can call this function.");

        _user;
        _l2Destination;
        _tokens;
        _amounts;
        /// @dev Some logic about handling each of the tokens
    }
}
