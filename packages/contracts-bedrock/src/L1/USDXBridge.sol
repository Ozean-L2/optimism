// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { OptimismPortal } from "src/L1/OptimismPortal.sol";
import { SystemConfig } from "src/L1/SystemConfig.sol";
import { ISemver } from "src/universal/ISemver.sol";

/// @dev To do: clarify mint/redeem logic with Hex Trust, deposit caps(?), yield reporting for ozUSD(?)
contract USDXBridge is OwnableUpgradeable, ReentrancyGuard, ISemver {
    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice Contract of the OptimismPortal.
    /// @custom:network-specific
    OptimismPortal public portal;

    /// @notice Address of the SystemConfig contract.
    SystemConfig public config;

    /// @notice Addresses of allow-listed stablecoins.
    mapping(address => bool) public allowlisted;

    /// INITIALIZE ///

    constructor() {
        initialize({
            _owner: address(0xdEaD),
            _portal: OptimismPortal(payable(address(0))),
            _config: SystemConfig(payable(address(0))),
            _stablecoins: new address[](0)
        });
    }

    function initialize(
        address _owner,
        OptimismPortal _portal,
        SystemConfig _config,
        address[] memory _stablecoins
    ) public initializer {
        __Ownable_init();
        transferOwnership(_owner);
        portal = _portal;
        config = _config;
        if (address(config) != address(0)) {
            usdx().approve(address(portal), ~uint256(0));

            uint256 length = _stablecoins.length;
            for (uint256 i; i < length; ++i) {
                allowlisted[_stablecoins[i]] = true;
            }
        }
    }

    /// BRIDGE TO ///

    /// @notice ...
    /// @param  _stablecoin Depositing stablecoin address.
    /// @param  _amount The amount of deposit stablecoin to be swapped for USDX.
    /// @param  _to Recieving address on L2.
    function bridge(
        address _stablecoin,
        uint256 _amount,
        address _to
    ) external nonReentrant {
        require(allowlisted[_stablecoin], "USDXBridge: Stablecoin not accepted.");
        /// @dev passing zero might be okay, need to double-check
        //require(_amount > 0, "USDXBridge: May not bridge nothing.");
        (bool sufficientLiquidity, uint256 bridgeAmount) = getBridgeLiquidity(_stablecoin, _amount);
        require(sufficientLiquidity, "USDXBridge: Insufficient bridge liquidity.");
        /// Ensure deposit is below deposit cap for each asset? could increment a mapping here

        IERC20Decimals(_stablecoin).transferFrom(msg.sender, address(this), _amount);
        portal.depositERC20Transaction({
            _to: _to,
            _mint: bridgeAmount,
            _value: bridgeAmount,
            _gasLimit: 1e6, /// @dev need to look into this more, how should it be set?
            _isCreation: false,
            _data: ""
        });

        /// Emits event for hex trust to manage assets?
    }

    /// BRIDGE FROM ///

    /// YIELD ///

    /// OWNER ///

    function setAllowlist(address _stablecoin, bool _set) external onlyOwner {
        allowlisted[_stablecoin] = _set;
    }

    function withdrawERC20(IERC20 _coin, uint256 _amount) external onlyOwner {
        _coin.transfer(msg.sender, _amount);
    }

    /// VIEW ///

    function usdx() public view returns (IERC20Decimals) {
        (address addr,) = config.gasPayingToken();
        return IERC20Decimals(addr);
    }

    function getBridgeLiquidity(
        address _stablecoin,
        uint256 _amount
    ) public view returns (bool, uint256) {
        uint8 depositDecimals = IERC20Decimals(_stablecoin).decimals();
        uint8 usdxDecimals = usdx().decimals();
        uint256 usdxBalance = usdx().balanceOf(address(this));
        bool sufficientLiquidity = (_amount * 10 ** usdxDecimals) <= (usdxBalance * 10 ** depositDecimals);
        uint256 bridgeAmount = (_amount * 10 ** usdxDecimals) / (10 ** depositDecimals);
        return (sufficientLiquidity, bridgeAmount);
    }
}

interface IERC20Decimals is IERC20 {
    function decimals() external view returns (uint8);
}
