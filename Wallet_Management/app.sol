// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title SimpleWallet
 * @dev A basic wallet management system on the blockchain.
 * This contract allows users to deposit, withdraw, and transfer Ether
 * by managing an internal balance for each user.
 *
 * Workflow (for CLI):
 * 1. User deposits Ether by calling `deposit()` and sending Ether (msg.value).
 * Their internal balance in the contract is credited.
 * 2. User checks their balance with `getMyBalance()` or `getBalance(address)`.
 * 3. User transfers their *internal balance* to another user's *internal balance*
 * by calling `transfer(recipientAddress, amount)`. This does not move Ether
 * out of the contract, only updates the internal accounting.
 * 4. User withdraws Ether from their internal balance back to their
 * external wallet by calling `withdraw(amount)`.
 */
contract SimpleWallet {

    // --- State Variables ---

    /**
     * @dev Mapping from a user's address to their balance (in Wei)
     * stored *within this contract*.
     */
    mapping(address => uint) public balances;

    // --- Events ---

    /**
     * @dev Emitted when a user deposits funds into their wallet.
     */
    event Deposited(address indexed user, uint amount);

    /**
     * @dev Emitted when a user withdraws funds from their wallet.
     */
    event Withdrawn(address indexed user, uint amount);

    /**
     * @dev Emitted when a user transfers funds to another user internally.
     */
    event Transferred(address indexed from, address indexed to, uint amount);

    // --- Functions ---

    /**
     * @dev Deposits Ether into the caller's internal balance.
     * The user must send Ether along with this function call.
     */
    function deposit() public payable {
        // msg.value is the amount of Ether (in Wei) sent with the transaction
        require(msg.value > 0, "Deposit amount must be greater than zero.");
        
        // Credit the user's internal balance
        balances[msg.sender] += msg.value;
        
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @dev Withdraws a specified amount of Ether from the user's
     * internal balance to their external wallet.
     * @param _amount The amount (in Wei) to withdraw.
     */
    function withdraw(uint _amount) public {
        // 1. Check: Ensure the user has sufficient funds
        require(balances[msg.sender] >= _amount, "Insufficient funds.");
        require(_amount > 0, "Withdrawal amount must be greater than zero.");

        // 2. Effects: Update the internal balance *before* sending Ether.
        // This is the "Checks-Effects-Interactions" pattern to prevent re-entrancy attacks.
        balances[msg.sender] -= _amount;

        // 3. Interaction: Send the Ether to the user's wallet
        // We use .call{} which is the recommended secure way to send Ether.
        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Withdrawal failed.");

        emit Withdrawn(msg.sender, _amount);
    }

    /**
     * @dev Transfers funds from the caller's internal balance to another
     * user's internal balance. This all happens within the contract.
     * @param _recipient The address of the user to receive the funds.
     * @param _amount The amount (in Wei) to transfer.
     */
    function transfer(address _recipient, uint _amount) public {
        // 1. Checks
        require(_recipient != address(0), "Cannot transfer to the zero address.");
        require(balances[msg.sender] >= _amount, "Insufficient funds.");
        require(_amount > 0, "Transfer amount must be greater than zero.");
        require(_recipient != msg.sender, "Cannot transfer to yourself.");

        // 2. Effects: Update both balances
        balances[msg.sender] -= _amount;
        balances[_recipient] += _amount;

        // 3. Interaction (Event)
        emit Transferred(msg.sender, _recipient, _amount);
    }

    // --- View Functions (Helpers for CLI) ---

    /**
     * @dev Gets the internal balance of the caller.
     */
    function getMyBalance() public view returns (uint) {
        return balances[msg.sender];
    }

    /**
     * @dev Gets the internal balance of any specified address.
     */
    function getBalance(address _user) public view returns (uint) {
        return balances[_user];
    }

    /**
     * @dev Shows the total Ether held by this entire contract.
     * This may be higher than the sum of balances if Ether is sent
     * directly to the contract address without calling deposit().
     */
    function getContractBalance() public view returns (uint) {
        return address(this).balance;
    }
}
