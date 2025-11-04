// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title CrowdFund
 * @dev A decentralized crowdfunding contract where contributors vote on fund disbursement.
 * This contract is intended for CLI interaction.
 *
 * Workflow:
 * 1. Manager deploys contract with a target amount (in Wei) and deadline (in days).
 * 2. Users call 'contribute()' to send Ether.
 * 3. After the deadline, anyone can call 'checkCampaignStatus()' to transition the state.
 * 4. IF FAILED: Contributors call 'getRefund()' to get their Ether back.
 * 5. IF SUCCESSFUL:
 * a. Manager calls 'createSpendingRequest()' for a project milestone.
 * b. Contributors call 'voteOnRequest()' to approve or reject the request.
 * c. Manager calls 'finalizeRequest()' to disburse funds if >50% approval (by contribution amount) is met.
 */
contract CrowdFund {

    // --- State Variables ---

    address payable public manager;
    uint public targetAmount; // The funding goal in Wei
    uint public deadline; // Unix timestamp
    uint public raisedAmount;
    uint public minContribution;
    uint public contributorsCount;

    // Maps a contributor's address to their total contribution
    mapping(address => uint) public contributors;

    // An array of all spending requests
    SpendingRequest[] public spendingRequests;

    // The current state of the campaign
    enum CampaignState { Fundraising, Successful, Failed }
    CampaignState public campaignState;

    // --- Structs ---

    /**
     * @dev Represents a request by the manager to spend a portion of the funds.
     */
    struct SpendingRequest {
        string description;       // What the funds will be used for
        uint amount;              // Amount requested in Wei
        address payable recipient; // Address to send the funds to
        bool isComplete;          // True if the request has been paid out
        uint approvalCount;       // The total 'yes' vote weight (weighted by contribution)
        mapping(address => bool) voters; // Tracks who has voted
    }

    // --- Events ---

    event ContributionMade(address indexed contributor, uint amount);
    event RefundIssued(address indexed contributor, uint amount);
    event RequestCreated(uint indexed requestId, string description, uint amount, address indexed recipient);
    event VoteCast(uint indexed requestId, address indexed voter, bool supports);
    event RequestFinalized(uint indexed requestId, bool approved, uint amountDisbursed);
    event CampaignFinished(CampaignState state, uint totalRaised);

    // --- Modifiers ---

    /**
     * @dev Restricts function execution to the manager.
     */
    modifier onlyManager() {
        require(msg.sender == manager, "Only manager can call this.");
        _;
    }

    /**
     * @dev Restaicts function execution to contributors.
     */
    modifier isContributor() {
        require(contributors[msg.sender] > 0, "Only contributors can call this.");
        _;
    }

    /**
     * @dev Restricts function execution to a specific campaign state.
     */
    modifier inState(CampaignState _state) {
        require(campaignState == _state, "Campaign not in correct state.");
        _;
    }

    // --- Functions ---

    /**
     * @dev Constructor to initialize the crowdfunding campaign.
     * @param _targetAmount The target funding goal in Wei.
     * @param _durationInDays The duration of the campaign in days from deployment.
     */
    constructor(uint _targetAmount, uint _durationInDays) {
        require(_targetAmount > 0, "Target must be greater than zero.");
        targetAmount = _targetAmount;
        deadline = block.timestamp + (_durationInDays * 1 days);
        manager = payable(msg.sender); // The deployer is the manager
        minContribution = 1e11; // Set a minimum (e.g., 100 Gwei) to prevent spam
        campaignState = CampaignState.Fundraising;
    }

    /**
     * @dev Allows any user to contribute to the campaign.
     * Must be called with `payable` (i.e., sending Ether).
     */
    function contribute() public payable inState(CampaignState.Fundraising) {
        require(block.timestamp < deadline, "Deadline has passed.");
        require(msg.value >= minContribution, "Contribution is below minimum.");

        // Add new contributor to count
        if (contributors[msg.sender] == 0) {
            contributorsCount++;
        }

        // Record contribution
        contributors[msg.sender] += msg.value;
        raisedAmount += msg.value;

        emit ContributionMade(msg.sender, msg.value);
    }

    /**
     * @dev Checks the campaign status after the deadline and updates the state.
     * This can be called by anyone.
     */
    function checkCampaignStatus() public inState(CampaignState.Fundraising) {
        require(block.timestamp >= deadline, "Campaign is still active.");

        if (raisedAmount >= targetAmount) {
            campaignState = CampaignState.Successful;
            emit CampaignFinished(CampaignState.Successful, raisedAmount);
        } else {
            campaignState = CampaignState.Failed;
            emit CampaignFinished(CampaignState.Failed, raisedAmount);
        }
    }

    /**
     * @dev Allows contributors to get a refund if the campaign fails.
     */
    function getRefund() public inState(CampaignState.Failed) {
        require(contributors[msg.sender] > 0, "Not a contributor or refund already claimed.");

        uint amountToRefund = contributors[msg.sender];
        
        // Re-entrancy guard: set amount to 0 *before* sending Ether.
        contributors[msg.sender] = 0;

        // Send the refund
        (bool sent, ) = payable(msg.sender).call{value: amountToRefund}("");
        require(sent, "Refund failed.");

        emit RefundIssued(msg.sender, amountToRefund);
    }

    /**
     * @dev Allows the manager to create a spending request.
     * @param _description Purpose of the spending request.
     * @param _amount Amount requested (in Wei).
     * @param _recipient The address to send the funds to.
     */
    function createSpendingRequest(string memory _description, uint _amount, address payable _recipient)
        public
        onlyManager
        inState(CampaignState.Successful)
    {
        require(_recipient != address(0), "Recipient address cannot be zero.");
        require(_amount <= address(this).balance, "Not enough funds in contract for this request.");

        // Add a new request to the array
        SpendingRequest storage newRequest = spendingRequests.push();
        newRequest.description = _description;
        newRequest.amount = _amount;
        newRequest.recipient = _recipient;
        newRequest.isComplete = false;
        newRequest.approvalCount = 0;

        emit RequestCreated(spendingRequests.length - 1, _description, _amount, _recipient);
    }

    /**
     * @dev Allows contributors to vote on a spending request.
     * @param _requestId The ID of the request (its index in the array).
     * @param _supports True to approve, false to reject.
     */
    function voteOnRequest(uint _requestId, bool _supports) public isContributor inState(CampaignState.Successful) {
        require(_requestId < spendingRequests.length, "Invalid request ID.");
        SpendingRequest storage request = spendingRequests[_requestId];

        require(!request.isComplete, "Request is already complete.");
        require(!request.voters[msg.sender], "You have already voted.");

        request.voters[msg.sender] = true;
        
        if (_supports) {
            // Vote is weighted by the contributor's total contribution
            request.approvalCount += contributors[msg.sender];
        }

        emit VoteCast(_requestId, msg.sender, _supports);
    }

    /**
     * @dev Allows the manager to finalize a request and disburse funds.
     * Requires more than 50% of the total raised funds (by contribution weight) to have approved.
     * @param _requestId The ID of the request to finalize.
     */
    function finalizeRequest(uint _requestId) public onlyManager inState(CampaignState.Successful) {
        require(_requestId < spendingRequests.length, "Invalid request ID.");
        SpendingRequest storage request = spendingRequests[_requestId];

        require(!request.isComplete, "Request is already complete.");
        require(request.amount <= address(this).balance, "Insufficient funds for this disbursement.");
        
        // Approval check: requires > 50% of *total raised funds*
        require(request.approvalCount > (raisedAmount / 2), "Request not approved by majority.");

        // Re-entrancy guard: update state *before* external call
        request.isComplete = true;

        // Send the funds
        (bool sent, ) = request.recipient.call{value: request.amount}("");
        require(sent, "Disbursement failed.");

        emit RequestFinalized(_requestId, true, request.amount);
    }

    // --- View Functions ---

    /**
     * @dev Get the contract's current Ether balance.
     */
    function getContractBalance() public view returns (uint) {
        return address(this).balance;
    }

    /**
     * @dev Get details about a specific spending request.
     */
    function getSpendingRequest(uint _requestId)
        public
        view
        returns (string memory, uint, address payable, bool, uint)
    {
        require(_requestId < spendingRequests.length, "Invalid request ID.");
        SpendingRequest storage request = spendingRequests[_requestId];
        return (
            request.description,
            request.amount,
            request.recipient,
            request.isComplete,
            request.approvalCount
        );
    }

    /**
     * @dev Get summary details of the campaign.
     */
    function getCampaignSummary()
        public
        view
        returns (address, uint, uint, uint, CampaignState, uint)
    {
        return (
            manager,
            targetAmount,
            raisedAmount,
            deadline,
            campaignState,
            spendingRequests.length
        );
    }
}
