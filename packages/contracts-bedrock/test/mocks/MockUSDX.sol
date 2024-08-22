// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDX is ERC20 {
    constructor() ERC20("USDX", "USDX") { }

    function mint(address _to, uint256 _value) external {
        _mint(_to, _value);
    }

    function withdraw(IERC20 _coin, address _to, uint256 _amount) external {
        _coin.transfer(_to, _amount);
    }
}
