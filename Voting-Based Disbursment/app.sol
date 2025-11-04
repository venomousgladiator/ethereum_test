// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title FundDisbursement
 * @dev A system for managing a project fund where a manager creates spending
 * requests and contributors (investors) vote to approve them.
 * Disbursement only happens if a majority of the contribution power
 * approves the request.
 *
 * Workflow:
 * 1. Deploy the contract, setting the `projectManager`.
 * 2. Contributors send Ether to the `contribute` function to fund the project
 * and gain voting power equal to their contribution.
 * 3. The manager calls `createRequest()` to propose a spending.
 * 4. Contributors call `voteOnRequest()` to approve or reject the request.
 * 5. Once a request has > 50% approval (by stake), the manager can call
 * `finalizeRequest()` to disburse the funds.
 */
contract FundDisbursement {

    // --- State Variables ---

    address public immutable projectManager;
    uint public totalContributions;
    uint public totalRequests;

    // Mapping: contributor address -> contribution amount (voting power)
    mapping(address => uint) public contributors;

    // A list of all spending requests
    SpendingRequest[] public requests;

    // --- Data Structures ---

    /**
     * @dev Represents a single spending request.
     */
    struct SpendingRequest {
        string description;     // Purpose of the spending
        address recipient;      // Address to send the funds to
        uint amount;            // Amount (in Wei) to send
        bool completed;         // True if the request has been paid out
        uint approvalCount;     // Sum of voting power (stake) that has approved
        
        // Tracks who has voted on this specific request to prevent double voting
        mapping(address => bool) voters;
    }

    // --- Events ---

    event ContributionReceived(address indexed contributor, uint amount);
    event RequestCreated(
        uint indexed requestId,
        address indexed manager,
        string description,
        address recipient,
        uint amount
    );
    event Voted(uint indexed requestId, address indexed contributor, bool approved);
    event RequestFinalized(uint indexed requestId, address recipient, uint amount);

    // --- Modifiers ---

    /**
     * @dev Restricts function access to the project manager.
     */
    modifier onlyManager() {
        require(msg.sender == projectManager, "Only the manager can call this.");
        _;
    }

    /**
     * @dev Restricts function access to contributors.
     */
    modifier onlyContributor() {
        require(contributors[msg.sender] > 0, "Only contributors can call this.");
        _;
    }

    // --- Constructor ---

    constructor(address _manager) {
        require(_manager != address(0), "Manager address cannot be zero.");
        projectManager = _manager;
    }

    // --- Core Functions ---

    /**
     * @dev Allows users to contribute Ether to the fund.
     * Their contribution amount becomes their voting power (stake).
     */
    function contribute() public payable {
        require(msg.value > 0, "Contribution must be greater than zero.");
        
        // Add contribution to the user's stake
        contributors[msg.sender] += msg.value;
        
        // Track total funds
        totalContributions += msg.value;

        emit ContributionReceived(msg.sender, msg.value);
    }

    /**
     * @dev Creates a new spending request. (Manager only)
     * @param _description Purpose of the spending.
     * @param _recipient The address to send funds to.
     * @param _amount The amount (in Wei) to send.
     */
    function createRequest(
        string memory _description,
        address _recipient,
        uint _amount
    ) public onlyManager {
        require(_recipient != address(0), "Recipient cannot be zero address.");
        require(_amount > 0, "Amount must be greater than zero.");
        require(
            _amount <= address(this).balance,
            "Amount exceeds contract balance."
        );

        // Add new request directly to storage
        requests.push();
        SpendingRequest storage newRequest = requests[requests.length - 1];
        
        // Initialize the request fields
        newRequest.description = _description;
        newRequest.recipient = _recipient;
        newRequest.amount = _amount;
        newRequest.completed = false;
        newRequest.approvalCount = 0;

        emit RequestCreated(
            requests.length - 1,
            msg.sender,
            _description,
            _recipient,
            _amount
        );

        // The manager's vote is automatically counted as an approval
        // This is a design choice; remove if manager should not vote.
        _vote(requests.length - 1, msg.sender, true);
    }

    /**
     * @dev Allows a contributor to vote on a spending request.
     * @param _requestId The ID (index) of the request to vote on.
     * @param _approve True to approve, false to reject.
     */
    function voteOnRequest(uint _requestId, bool _approve) public onlyContributor {
        require(_requestId < requests.length, "Request does not exist.");
        
        _vote(_requestId, msg.sender, _approve);
    }

    /**
     * @dev Internal logic for casting a vote.
     */
    function _vote(uint _requestId, address _voter, bool _approve) internal {
        SpendingRequest storage request = requests[_requestId];

        require(!request.completed, "Request is already completed.");
        require(
            !request.voters[_voter],
            "You have already voted on this request."
        );

        // Mark the contributor as having voted
        request.voters[_voter] = true;

        // If they approve, add their stake to the approval count
        if (_approve) {
            request.approvalCount += contributors[_voter];
        }

        emit Voted(_requestId, _voter, _approve);
    }

    /**
     * @dev Finalizes a request, paying the recipient if approved. (Manager only)
     * Anyone could be allowed to call this, but restricting to the manager
     * is a common pattern.
     * @param _requestId The ID (index) of the request to finalize.
     */
    function finalizeRequest(uint _requestId) public onlyManager {
        require(_requestId < requests.length, "Request does not exist.");

        SpendingRequest storage request = requests[_requestId];

        require(!request.completed, "Request is already completed.");

        // Democratic check: Has more than 50% of the total stake approved?
        require(
            request.approvalCount > (totalContributions / 2),
            "Request has not reached majority approval."
        );

        require(
            address(this).balance >= request.amount,
            "Insufficient funds in contract to pay this request."
        );

        // Mark as completed *before* sending Ether (Checks-Effects-Interactions)
        request.completed = true;

        // Send the funds
        (bool success, ) = request.recipient.call{value: request.amount}("");
        require(success, "Fund transfer failed.");

        emit RequestFinalized(_requestId, request.recipient, request.amount);
    }

    // --- View Functions ---

    /**
     * @dev Gets the total funds held by the contract.
     */
    function getContractBalance() public view returns (uint) {
        return address(this).balance;
    }

    /**
* @dev Returns details for a single request.
*/
    function getRequest(uint _requestId)
        public
        view
        returns (
            string memory description,
            address recipient,
            uint amount,
            bool completed,
            uint approvalCount
        )
    {
        require(_requestId < requests.length, "Request does not exist.");
        SpendingRequest storage r = requests[_requestId];
        return (
            r.description,
            r.recipient,
            r.amount,
            r.completed,
            r.approvalCount
        );
    }

    /**
     * @dev Returns the total number of requests.
     */
    function getRequestCount() public view returns (uint) {
        return requests.length;
    }
}
