// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// Rebasing token - does NOT conform to the ERC20 standard due to no event emitted on rebase
/// Reference implementation: https://vscode.blockscan.com/ethereum/0x17144556fd3424edc8fc8a4c940b2d04936d17eb
contract OzUSD is IERC20, ReentrancyGuard {
    string public constant name = "Ozean USD";

    string public constant symbol = "ozUSD";

    uint8 public constant decimals = 18;

    uint256 private totalShares;

    /**
     * @dev ozUSD balances are dynamic and are calculated based on the accounts' shares
     * and the total amount of USDX controlled by the protocol. Account shares aren't
     * normalized, so the contract also stores the sum of all shares to calculate
     * each account's token balance which equals to:
     *
     *   shares[account] * _getTotalPooledUSDX() / totalShares
     */
    mapping(address => uint256) private shares;

    /**
     * @dev Allowances are denominated in tokens, not token shares.
     */
    mapping(address => mapping(address => uint256)) private allowances;

    /**
     * @notice An executed shares transfer from `sender` to `recipient`.
     * @dev emitted in pair with an ERC20-defined `Transfer` event.
     */
    event TransferShares(address indexed from, address indexed to, uint256 sharesValue);

    /**
     * @notice An executed `burnShares` request
     *
     * @dev Reports simultaneously burnt shares amount and corresponding ozUSD amount.
     * The ozUSD amount is calculated twice: before and after the burning incurred rebase.
     *
     * @param account holder of the burnt shares
     * @param preRebaseTokenAmount amount of ozUSD the burnt shares corresponded to before the burn
     * @param postRebaseTokenAmount amount of ozUSD the burnt shares corresponded to after the burn
     * @param sharesAmount amount of burnt shares
     */
    event SharesBurnt(
        address indexed account, uint256 preRebaseTokenAmount, uint256 postRebaseTokenAmount, uint256 sharesAmount
    );

    constructor(uint256 _sharesAmount) payable {
        _mintShares(address(0xdead), _sharesAmount);
        _emitTransferAfterMintingShares(address(0xdead), _sharesAmount);
    }

    /// EXTERNAL ///

    receive() external payable { }

    /// @dev The `_amount` argument is the amount of tokens, not shares.
    function transfer(address _recipient, uint256 _amount) external nonReentrant returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    /// @dev The `_amount` argument is the amount of tokens, not shares.
    function transferFrom(address _sender, address _recipient, uint256 _amount) external nonReentrant returns (bool) {
        _spendAllowance(_sender, msg.sender, _amount);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    /// @dev The `_amount` argument is the amount of tokens, not shares.
    function approve(address _spender, uint256 _amount) external nonReentrant returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    /// @dev The `_addedValue` argument is the amount of tokens, not shares.
    function increaseAllowance(address _spender, uint256 _addedValue) external nonReentrant returns (bool) {
        _approve(msg.sender, _spender, allowances[msg.sender][_spender] + _addedValue);
        return true;
    }

    /// @dev The `_subtractedValue` argument is the amount of tokens, not shares.
    function decreaseAllowance(address _spender, uint256 _subtractedValue) external nonReentrant returns (bool) {
        uint256 currentAllowance = allowances[msg.sender][_spender];
        require(currentAllowance >= _subtractedValue, "OzUSD: ALLOWANCE_BELOW_ZERO");
        _approve(msg.sender, _spender, currentAllowance - _subtractedValue);
        return true;
    }

    /// @dev The `_sharesAmount` argument is the amount of shares, not tokens.
    function transferShares(address _recipient, uint256 _sharesAmount) external nonReentrant returns (uint256) {
        _transferShares(msg.sender, _recipient, _sharesAmount);
        uint256 tokensAmount = getPooledUSDXByShares(_sharesAmount);
        _emitTransferEvents(msg.sender, _recipient, tokensAmount, _sharesAmount);
        return tokensAmount;
    }

    /// @dev The `_sharesAmount` argument is the amount of shares, not tokens.
    function transferSharesFrom(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    )
        external
        nonReentrant
        returns (uint256)
    {
        uint256 tokensAmount = getPooledUSDXByShares(_sharesAmount);
        _spendAllowance(_sender, msg.sender, tokensAmount);
        _transferShares(_sender, _recipient, _sharesAmount);
        _emitTransferEvents(_sender, _recipient, tokensAmount, _sharesAmount);
        return tokensAmount;
    }

    function mintOzUSD(address _to, uint256 _usdxAmount) external payable nonReentrant {
        require(_usdxAmount != 0, "OzUSD: Amount zero");
        require(msg.value == _usdxAmount, "OzUSD: Insufficient USDX transfer");

        /// @dev Have to minus `_usdxAmount` from denominator given the transfer of funds has already occured
        uint256 sharesToMint = (_usdxAmount * totalShares) / (_getTotalPooledUSDX() - _usdxAmount);
        uint256 newTotalShares = _mintShares(_to, sharesToMint);

        _emitTransferAfterMintingShares(_to, newTotalShares);
    }

    /// @dev spender must approve contract, even if owner of coins
    function redeemOzUSD(address _from, uint256 _ozUSDAmount) external nonReentrant {
        require(_ozUSDAmount != 0, "OzUSD: Amount zero");
        _spendAllowance(_from, msg.sender, _ozUSDAmount);

        uint256 sharesToBurn = getSharesByPooledUSDX(_ozUSDAmount);
        _burnShares(_from, sharesToBurn);

        (bool s,) = _from.call{ value: _ozUSDAmount }("");
        assert(s);

        _emitTransferEvents(msg.sender, address(0), _ozUSDAmount, sharesToBurn);
    }

    /// VIEW ///

    /**
     * @return the amount of tokens owned by the `_account`.
     *
     * @dev Balances are dynamic and equal the `_account`'s share in the amount of the
     * total USDX controlled by the protocol. See `sharesOf`.
     */
    function balanceOf(address _account) external view returns (uint256) {
        return getPooledUSDXByShares(shares[_account]);
    }

    /**
     * @return the remaining number of tokens that `_spender` is allowed to spend
     * on behalf of `_owner` through `transferFrom`. This is zero by default.
     *
     * @dev This value changes when `approve` or `transferFrom` is called.
     */
    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function sharesOf(address _account) external view returns (uint256) {
        return shares[_account];
    }

    /// @return the amount of shares that corresponds to `_usdxAmount` protocol-controlled USDX.
    function getSharesByPooledUSDX(uint256 _usdxAmount) public view returns (uint256) {
        return (_usdxAmount * totalShares) / _getTotalPooledUSDX();
    }

    /// @return the amount of USDX that corresponds to `_sharesAmount` token shares.
    function getPooledUSDXByShares(uint256 _sharesAmount) public view returns (uint256) {
        return (_sharesAmount * _getTotalPooledUSDX()) / totalShares;
    }

    /**
     * @return the amount of tokens in existence.
     *
     * @dev Always equals to `_getTotalPooledUSDX()` since token amount
     * is pegged to the total amount of USDX controlled by the protocol.
     */
    function totalSupply() external view returns (uint256) {
        return _getTotalPooledUSDX();
    }

    /// INTERNAL ///

    function _getTotalPooledUSDX() internal view returns (uint256) {
        return address(this).balance;
    }

    function _sharesOf(address _account) internal view returns (uint256) {
        return shares[_account];
    }

    /// @notice Moves `_amount` tokens from `_sender` to `_recipient`.
    function _transfer(address _sender, address _recipient, uint256 _amount) internal {
        uint256 _sharesToTransfer = getSharesByPooledUSDX(_amount);
        _transferShares(_sender, _recipient, _sharesToTransfer);
        _emitTransferEvents(_sender, _recipient, _amount, _sharesToTransfer);
    }

    function _approve(address _owner, address _spender, uint256 _amount) internal {
        require(_owner != address(0), "OzUSD: APPROVE_FROM_ZERO_ADDR");
        require(_spender != address(0), "OzUSD: APPROVE_TO_ZERO_ADDR");

        allowances[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }

    function _spendAllowance(address _owner, address _spender, uint256 _amount) internal {
        uint256 currentAllowance = allowances[_owner][_spender];
        if (currentAllowance != ~uint256(0)) {
            require(currentAllowance >= _amount, "OzUSD: ALLOWANCE_EXCEEDED");
            _approve(_owner, _spender, currentAllowance - _amount);
        }
    }

    function _transferShares(address _sender, address _recipient, uint256 _sharesAmount) internal {
        require(_sender != address(0), "OzUSD: TRANSFER_FROM_ZERO_ADDR");
        require(_recipient != address(0), "OzUSD: TRANSFER_TO_ZERO_ADDR");
        require(_recipient != address(this), "OzUSD: TRANSFER_TO_STETH_CONTRACT");

        uint256 currentSenderShares = shares[_sender];
        require(_sharesAmount <= currentSenderShares, "OzUSD: BALANCE_EXCEEDED");

        shares[_sender] = currentSenderShares - _sharesAmount;
        shares[_recipient] = shares[_recipient] + _sharesAmount;
    }

    /**
     * @notice Creates `_sharesAmount` shares and assigns them to `_recipient`, increasing the total amount of shares.
     * @dev This doesn't increase the token total supply.
     */
    function _mintShares(address _recipient, uint256 _sharesAmount) internal returns (uint256 newTotalShares) {
        require(_recipient != address(0), "OzUSD: MINT_TO_ZERO_ADDR");

        newTotalShares = totalShares + _sharesAmount;
        totalShares = newTotalShares;
        shares[_recipient] += _sharesAmount;
    }

    /**
     * @notice Destroys `_sharesAmount` shares from `_account`'s holdings, decreasing the total amount of shares.
     * @dev This doesn't decrease the token total supply.
     * @dev Suspect the pre and post Rebase amounts aren't necessary for this use-case
     */
    function _burnShares(address _account, uint256 _sharesAmount) internal returns (uint256 newTotalShares) {
        require(_account != address(0), "OzUSD: BURN_FROM_ZERO_ADDR");

        uint256 accountShares = shares[_account];
        require(_sharesAmount <= accountShares, "OzUSD: BALANCE_EXCEEDED");

        uint256 preRebaseTokenAmount = getPooledUSDXByShares(_sharesAmount);

        newTotalShares = totalShares - _sharesAmount;
        totalShares = newTotalShares;
        shares[_account] = accountShares - _sharesAmount;

        uint256 postRebaseTokenAmount = getPooledUSDXByShares(_sharesAmount);

        emit SharesBurnt(_account, preRebaseTokenAmount, postRebaseTokenAmount, _sharesAmount);
    }

    function _emitTransferEvents(address _from, address _to, uint256 _tokenAmount, uint256 _sharesAmount) internal {
        emit Transfer(_from, _to, _tokenAmount);
        emit TransferShares(_from, _to, _sharesAmount);
    }

    /// @dev Emits {Transfer} and {TransferShares} events where `from` is 0 address. Indicates mint events.
    function _emitTransferAfterMintingShares(address _to, uint256 _sharesAmount) internal {
        _emitTransferEvents(address(0), _to, getPooledUSDXByShares(_sharesAmount), _sharesAmount);
    }
}
