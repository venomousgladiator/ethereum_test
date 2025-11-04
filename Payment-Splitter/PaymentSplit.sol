// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// We will use OpenZeppelin's audited PaymentSplitter contract.
// This is the most secure way to build this.
import "@openzeppelin/contracts/finance/PaymentSplitter.sol";

/**
 * @title SimpleSplitter
 * @dev This contract takes a list of addresses in its constructor and splits
 * any Ether sent to it equally among them.
 *
 * It uses OpenZeppelin's PaymentSplitter, which implements the secure
 * "pull-payment" pattern. Participants must call 'release' to get their funds.
 */
contract SimpleSplitter is PaymentSplitter {

    /**
     * @dev Creates the splitter and sets up the equal shares.
     * @param _payees A list of addresses that will share the payments.
     */
    constructor(address[] memory _payees)
        // We call the parent constructor (PaymentSplitter)
        PaymentSplitter(_payees, _generateEqualShares(_payees.length))
    {
        // The PaymentSplitter constructor handles all the setup.
    }

    /**
     * @dev A private helper function to create an array of '1's.
     * This ensures every payee has an equal share.
     */
    function _generateEqualShares(uint256 _length)
        private
        pure
        returns (uint256[] memory)
    {
        require(_length > 0, "No payees provided");
        uint256[] memory shares = new uint256[](_length);
        for (uint256 i = 0; i < _length; i++) {
            shares[i] = 1;
        }
        return shares;
    }

    /**
     * @dev This function is required for the contract to receive Ether.
     * Any ETH sent directly to the contract's address will be
     * accepted and held for the payees to withdraw.
     *
     * The 'receive' function is a special function that is executed
     * when the contract receives plain Ether (with no data).
     */
    receive() external payable override {
        // This function body can be empty. Its only purpose is to
        // allow the contract to accept ETH. The PaymentSplitter
        // logic will handle the accounting of the received funds.
    }
}

