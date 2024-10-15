// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { OzUSD } from "./OzUSD.sol";

/// Auto-compounding token of ozUSD
/// Reference implementation: https://vscode.blockscan.com/ethereum/0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0
contract WozUSD is ERC20, ReentrancyGuard {
    OzUSD public immutable ozUSD;

    constructor(OzUSD _ozUSD) ERC20("Wrapped Ozean USD", "wozUSD") {
        ozUSD = _ozUSD;
    }

    function wrap(uint256 _ozUSDAmount) external nonReentrant returns (uint256 wozUSDAmount) {
        require(_ozUSDAmount > 0, "WozUSD: Can't wrap zero ozUSD");
        ozUSD.transferFrom(msg.sender, address(this), _ozUSDAmount);
        wozUSDAmount = ozUSD.getSharesByPooledUSDX(_ozUSDAmount);
        _mint(msg.sender, wozUSDAmount);
    }

    function unwrap(uint256 _wozUSDAmount) external nonReentrant returns (uint256 ozUSDAmount) {
        require(_wozUSDAmount > 0, "WozUSD: Can't unwrap zero wozUSD");
        _burn(msg.sender, _wozUSDAmount);
        ozUSDAmount = ozUSD.getPooledUSDXByShares(_wozUSDAmount);
        ozUSD.transfer(msg.sender, ozUSDAmount);
    }

    /// @notice Get amount of ozUSD for a one wozUSD
    function ozUSDPerToken() external view returns (uint256) {
        return ozUSD.getPooledUSDXByShares(1 ether);
    }

    /// @notice Get amount of wozUSD for a one ozUSD
    function tokensPerOzUSD() external view returns (uint256) {
        return ozUSD.getSharesByPooledUSDX(1 ether);
    }
}
