// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { OptimismPortal } from "src/L1/OptimismPortal.sol";
import { ISemver } from "src/universal/ISemver.sol";

/// @dev Recieves USDX from Hex Trust, pushes it to the L2, and deposits to associated ozUSD contract
contract OzUSDYieldManager is Ownable, ReentrancyGuard, ISemver {

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice Contract of the Optimism Portal.
    /// @custom:network-specific
    OptimismPortal public immutable portal;

    IERC20 public immutable USDX;

    address public immutable ozUSD;

    /// @dev events

    /// SETUP ///

    constructor(address _owner, IERC20 _USDX, OptimismPortal _portal, address _ozUSD) {
        _transferOwnership(_owner);
        USDX = _USDX;
        portal = _portal;
        ozUSD = _ozUSD;
    }

    /// OWNER ///

    function rebase(uint256 _amount) external nonReentrant onlyOwner {

        USDX.transferFrom(msg.sender, address(this), _amount);

        portal.depositERC20Transaction({
            _to: ozUSD,
            _mint: _amount,
            _value: _amount,
            _gasLimit: 21000,
            /// @dev portal.minimumGasLimit(0) Might need to be more if calldata is passed
            _isCreation: false,
            _data: ""
        });
    }

    /// VIEW ///
}
