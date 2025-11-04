// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title SimpleToken
 * @dev A basic implementation of the ERC-20 token standard.
 * This contract allows for:
 * 1. Minting new tokens (only by the owner).
 * 2. Transferring tokens between addresses.
 * 3. Approving other addresses (spenders) to transfer tokens on one's behalf.
 * 4. Tracking total supply and individual balances.
 */
contract SimpleToken {

    // --- State Variables ---

    // Token metadata
    string public constant name = "SimpleToken";
    string public constant symbol = "STKN";
    uint8 public constant decimals = 18; // 18 is common for divisibility

    // Total supply of tokens
    uint256 public totalSupply;

    // Balances: mapping from an address to its token balance
    mapping(address => uint256) public balanceOf;

    // Allowances: mapping of (owner -> spender -> amount)
    // This allows a spender to withdraw from an owner's account up to a certain amount.
    mapping(address => mapping(address => uint256)) public allowance;

    // The address that deployed the contract (the owner)
    address public immutable owner;

    // --- Events ---

    /**
     * @dev Emitted when tokens are transferred.
     * `from` is address(0) when tokens are minted.
     */
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 value
    );

    /**
     * @dev Emitted when an allowance is set or updated.
     */
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    // --- Modifier ---

    /**
     * @dev Restricts a function to be callable only by the contract owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function.");
        _;
    }

    // --- Constructor ---

    /**
     * @dev Sets the deploying address as the contract owner.
     */
    constructor() {
        owner = msg.sender;
    }

    // --- Custom Functions ---

    /**
     * @dev Mints new tokens and assigns them to a specified address.
     * Can only be called by the contract owner.
     * @param _to The address that will receive the minted tokens.
     * @param _amount The amount of tokens to mint (in the smallest unit, e.g., Wei).
     */
    function mint(address _to, uint256 _amount) public onlyOwner {
        require(_to != address(0), "Cannot mint to the zero address.");
        require(_amount > 0, "Amount must be greater than zero.");

        // Increase total supply
        totalSupply += _amount;

        // Add tokens to the recipient's balance
        balanceOf[_to] += _amount;

        // Emit a Transfer event from the zero address (standard for minting)
        emit Transfer(address(0), _to, _amount);
    }

    // --- ERC-20 Core Functions ---

    /**
     * @dev Transfers tokens from the caller's account to a recipient.
     * @param _to The address to transfer tokens to.
     * @param _amount The amount of tokens to transfer.
     * @return A boolean indicating whether the operation succeeded.
     */
    function transfer(address _to, uint256 _amount) public returns (bool) {
        address _from = msg.sender;

        require(_to != address(0), "ERC20: transfer to the zero address");
        require(
            balanceOf[_from] >= _amount,
            "ERC20: transfer amount exceeds balance"
        );

        // Perform the transfer
        balanceOf[_from] -= _amount;
        balanceOf[_to] += _amount;

        emit Transfer(_from, _to, _amount);
        return true;
    }

    /**
     * @dev Approves a spender to withdraw a specific amount of tokens
     * from the caller's account.
     * @param _spender The address that will be allowed to spend tokens.
     * @param _amount The maximum amount of tokens the spender is allowed.
     * @return A boolean indicating whether the operation succeeded.
     */
    function approve(address _spender, uint256 _amount) public returns (bool) {
        address _owner = msg.sender;
        
        require(_spender != address(0), "ERC20: approve to the zero address");

        // Set the allowance
        allowance[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
        return true;
    }

    /**
     * @dev Transfers tokens from one address to another, using the
     * allowance mechanism. The caller must have been approved by the `_from` address.
     * @param _from The address to transfer tokens from.
     * @param _to The address to transfer tokens to.
     * @param _amount The amount of tokens to transfer.
     * @return A boolean indicating whether the operation succeeded.
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) public returns (bool) {
        address _spender = msg.sender;
        
        require(_from != address(0), "ERC20: transfer from the zero address");
        require(_to != address(0), "ERC20: transfer to the zero address");
        require(
            balanceOf[_from] >= _amount,
            "ERC20: transfer amount exceeds balance"
        );
        
        uint256 currentAllowance = allowance[_from][_spender];
        require(
            currentAllowance >= _amount,
            "ERC20: transfer amount exceeds allowance"
        );

        // Perform the transfer
        balanceOf[_from] -= _amount;
        balanceOf[_to] += _amount;

        // Reduce the spender's allowance
        // Note: This check prevents underflow if allowance is type(uint256).max
        if (currentAllowance != type(uint256).max) {
            allowance[_from][_spender] -= _amount;
        }

        emit Transfer(_from, _to, _amount);
        return true;
    }
}
