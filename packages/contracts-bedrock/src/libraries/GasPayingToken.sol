// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Storage } from "src/libraries/Storage.sol";
import { Constants } from "src/libraries/Constants.sol";

/// @title GasPayingToken
/// @notice Handles reading and writing the custom gas token to storage.
///         To be used in any place where gas token information is read or
///         written to state. If multiple contracts use this library, the
///         values in storage should be kept in sync between them.
library GasPayingToken {
    /// @notice The storage slot that contains the address and decimals of the gas paying token
    bytes32 internal constant GAS_PAYING_TOKEN_SLOT = bytes32(uint256(keccak256("opstack.gaspayingtoken")) - 1);

    /// @notice The storage slot that contains the ERC20 `name()` of the gas paying token
    bytes32 internal constant GAS_PAYING_TOKEN_NAME_SLOT = bytes32(uint256(keccak256("opstack.gaspayingtokenname")) - 1);

    /// @notice the storage slot that contains the ERC20 `symbol()` of the gas paying token
    bytes32 internal constant GAS_PAYING_TOKEN_SYMBOL_SLOT =
        bytes32(uint256(keccak256("opstack.gaspayingtokensymbol")) - 1);

    /// @notice Reads the gas paying token and its decimals from the magic
    ///         storage slot. If nothing is set in storage, then the ether
    ///         address is returned instead.
    function get() internal view returns (address addr_, uint8 decimals_, string memory name_, string memory symbol_) {
        bytes32 slot = Storage.getBytes32(GAS_PAYING_TOKEN_SLOT);
        addr_ = address(uint160(uint256(slot) & uint256(type(uint160).max)));
        if (addr_ == address(0)) {
            addr_ = Constants.ETHER;
            decimals_ = 18;
            name_ = "Ether";
            symbol_ = "ETH";
        } else {
            decimals_ = uint8(uint256(slot) >> 160);
            name_ = string(abi.encodePacked(Storage.getBytes32(GAS_PAYING_TOKEN_NAME_SLOT)));
            symbol_ = string(abi.encodePacked(Storage.getBytes32(GAS_PAYING_TOKEN_SYMBOL_SLOT)));
        }
    }

    /// @notice Writes the gas paying token, its decimals, name and symbol to the magic storage slot.
    function set(address _token, uint8 _decimals, string memory _name, string memory _symbol) internal {
        Storage.setBytes32(GAS_PAYING_TOKEN_SLOT, bytes32(uint256(_decimals) << 160 | uint256(uint160(_token))));
        Storage.setBytes32(GAS_PAYING_TOKEN_NAME_SLOT, bytes32(abi.encodePacked(_name)));
        Storage.setBytes32(GAS_PAYING_TOKEN_SYMBOL_SLOT, bytes32(abi.encodePacked(_symbol)));
    }
}
