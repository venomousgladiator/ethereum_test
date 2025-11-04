// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Lottery
 * @dev A simple, decentralized lottery system.
 *
 * Workflow (for CLI):
 * 1. Manager deploys the contract, setting an entry fee (in Wei) and a minimum number of participants.
 * 2. Participants call `enter()` and send the exact entry fee as `msg.value`.
 * 3. Anyone can view the current prize pool with `getBalance()` or see participants with `getParticipants()`.
 * 4. Once `getParticipants().length` is >= `minParticipants`, the manager can call `pickWinner()`.
 * 5. `pickWinner()`:
 * - Selects a pseudo-random winner.
 * - Transfers the entire prize pool to the winner.
 * - Resets the participant list for the next round.
 * 6. The `recentWinner` variable is updated.
 */
contract Lottery {

    // --- State Variables ---

    address public manager;
    uint public entryFee;
    uint public minParticipants;

    // List of participants who have entered the current round
    // 'payable' is required to send the prize to the winner
    address payable[] public participants;

    // The winner of the most recent lottery round
    address public recentWinner;

    // --- Events ---

    /**
     * @dev Emitted when a participant successfully enters the lottery.
     * @param participant The address of the participant.
     */
    event LotteryEntered(address indexed participant);

    /**
     * @dev Emitted when a winner is picked and paid.
     * @param winner The address of the winner.
     * @param prize The total prize amount (in Wei) transferred to the winner.
     */
    event WinnerPicked(address indexed winner, uint prize);

    // --- Modifiers ---

    /**
     * @dev Restricts function execution to the manager (the deployer).
     */
    modifier onlyManager() {
        require(msg.sender == manager, "Only the manager can call this function.");
        _;
    }

    // --- Functions ---

    /**
     * @dev Constructor: Sets up the lottery parameters upon deployment.
     * @param _entryFee The cost (in Wei) to enter the lottery.
     * @param _minParticipants The minimum number of participants required to pick a winner.
     */
    constructor(uint _entryFee, uint _minParticipants) {
        require(_entryFee > 0, "Entry fee must be greater than zero.");
        require(_minParticipants > 0, "Minimum participants must be greater than zero.");
        
        manager = msg.sender;
        entryFee = _entryFee;
        minParticipants = _minParticipants;
    }

    /**
     * @dev Allows a participant to enter the lottery.
     * Must be called with a `msg.value` (Ether) equal to the `entryFee`.
     */
    function enter() public payable {
        // 1. Check if the sent value is exactly the entry fee
        require(msg.value == entryFee, "Must send exact entry fee.");

        // 2. Add the participant to the array
        participants.push(payable(msg.sender));

        // 3. Emit an event
        emit LotteryEntered(msg.sender);
    }

    /**
     * @dev Selects a winner, pays them the entire contract balance, and resets the lottery.
     * Can only be called by the manager.
     * Can only be called after the minimum number of participants have joined.
     */
    function pickWinner() public onlyManager {
        // 1. Check if the minimum participant count has been met
        require(participants.length >= minParticipants, "Not enough participants yet.");

        // 2. Pick a "random" winner
        // WARNING: This is pseudo-random and not secure for a real-world, high-stakes
        // lottery as miners can influence the outcome. For a truly fair system,
        // a Chainlink VRF (Verifiable Random Function) oracle is recommended.
        uint randomIndex = uint(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, participants.length))) % participants.length;
        address payable winner = participants[randomIndex];
        recentWinner = winner;

        // 3. Get the total prize pool (all Ether held by this contract)
        uint prize = address(this).balance;

        // 4. Reset the participants list *before* sending Ether.
        // This is a security best practice to prevent re-entrancy attacks.
        participants = new address payable[](0);

        // 5. Send the prize to the winner
        (bool success, ) = winner.call{value: prize}("");
        require(success, "Prize transfer failed.");

        // 6. Emit the event
        emit WinnerPicked(winner, prize);
    }

    // --- View Functions (Helpers for CLI) ---

    /**
     * @dev Returns the list of all participants in the current round.
     */
    function getParticipants() public view returns (address payable[] memory) {
        return participants;
    }

    /**
     * @dev Returns the current prize pool (total Ether in the contract).
     */
    function getBalance() public view returns (uint) {
        return address(this).balance;
    }

    /**
     * @dev Returns the address of the manager.
     */
    function getManager() public view returns (address) {
        return manager;
    }
}
