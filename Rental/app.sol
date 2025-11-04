// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title RentalAgreement
 * @dev A smart contract to manage a rental agreement, escrow for security deposit,
 * and dispute resolution by a designated legal professional.
 *
 * Workflow:
 * 1. Owner deploys contract with Tenant, Legal Professional, rent, deposit,
 * lease start/end times, and a hash of the physical agreement.
 * 2. Tenant signs the agreement (calls `tenantSign`).
 * 3. Legal Professional signs the agreement (calls `legalSign`).
 * 4. Once all parties sign, the state becomes `Signed`.
 * 5. Tenant pays the security deposit (calls `paySecurityDeposit`).
 * 6. Once deposit is paid, the state becomes `Funded`.
 * 7. After the lease a/greement.
 */
contract RentalAgreement {

    // --- Enums ---

    /**
     * @dev Represents the current state of the rental agreement.
     */
    enum AgreementState {
        Created,          // Initial state, awaiting signatures
        Signed,           // All parties have signed, awaiting deposit
        Funded,           // Deposit paid, lease is active
        Terminated,       // Lease term ended, awaiting deposit resolution
        Disputed,         // Awaiting legal professional's resolution
        Completed,        // Deposit disbursed, contract finalized
        Cancelled         // Cancelled before funding
    }

    // --- State Variables ---

    // Parties
    address public immutable owner;            // Landlord
    address public immutable tenant;
    address public immutable legalProfessional;

    // Financials
    uint public immutable rentAmount;         // Monthly rent (for info)
    uint public immutable securityDeposit;

    // Terms
    uint public immutable leaseStartDate;     // Unix timestamp
    uint public immutable leaseEndDate;       // Unix timestamp
    bytes32 public immutable agreementHash;   // Keccak256 hash of the off-chain doc

    // State
    AgreementState public state;
    bool public tenantSigned;
    bool public legalSigned;
    
    // Deposit resolution proposal
    uint private proposedTenantShare;
    uint private proposedOwnerShare;
    bool public ownerProposedSplit;
    bool public tenantAgreedToSplit;
    
    // --- Events ---

    event AgreementSigned(address indexed signer, uint timestamp);
    event DepositPaid(address indexed tenant, uint amount);
    event AgreementTerminated(uint timestamp);
    event SplitProposed(uint tenantShare, uint ownerShare);
    event SplitAgreed(uint tenantShare, uint ownerShare);
    event DisputeRaised(address indexed raisedBy);
    event DisputeResolved(address indexed resolver, uint tenantShare, uint ownerShare);
    event AgreementCancelled();
    event FundsDisbursed(address indexed to, uint amount);

    // --- Modifiers ---

    modifier onlyRole(address _role) {
        require(msg.sender == _role, "Caller is not authorized for this role.");
        _;
    }

    modifier inState(AgreementState _state) {
        require(state == _state, "Function cannot be called in the current state.");
        _;
    }
    
    modifier onlyAfter(uint _timestamp) {
        require(block.timestamp >= _timestamp, "Action cannot be taken before this time.");
        _;
    }

    // --- Constructor ---

    /**
     * @dev Creates the rental agreement.
     * @param _tenant The tenant's address.
     * @param _legalProfessional The legal professional's address (arbiter).
     * @param _rentAmount The monthly rent amount (in Wei).
     * @param _securityDeposit The security deposit amount (in Wei).
     * @param _leaseStartDate The Unix timestamp for lease start.
     * @param _leaseEndDate The Unix timestamp for lease end.
     * @param _agreementHash A Keccak256 hash of the off-chain rental document.
     */
    constructor(
        address _tenant,
        address _legalProfessional,
        uint _rentAmount,
        uint _securityDeposit,
        uint _leaseStartDate,
        uint _leaseEndDate,
        bytes32 _agreementHash
    ) {
        require(_tenant != address(0) && _legalProfessional != address(0), "Invalid addresses");
        require(_leaseEndDate > _leaseStartDate, "Lease end must be after start");
        require(_securityDeposit > 0, "Security deposit must be greater than zero");

        owner = msg.sender;
        tenant = _tenant;
        legalProfessional = _legalProfessional;
        rentAmount = _rentAmount;
        securityDeposit = _securityDeposit;
        leaseStartDate = _leaseStartDate;
        leaseEndDate = _leaseEndDate;
        agreementHash = _agreementHash;
        
        state = AgreementState.Created;
    }

    // --- Functions ---

    /**
     * @dev Called by the Tenant to sign and agree to the terms.
     */
    function tenantSign() external onlyRole(tenant) inState(AgreementState.Created) {
        tenantSigned = true;
        emit AgreementSigned(tenant, block.timestamp);
        _checkAllSigned();
    }

    /**
     * @dev Called by the Legal Professional to sign and agree to act as arbiter.
     */
    function legalSign() external onlyRole(legalProfessional) inState(AgreementState.Created) {
        legalSigned = true;
        emit AgreementSigned(legalProfessional, block.timestamp);
        _checkAllSigned();
    }

    /**
     * @dev Internal function to update state once all parties have signed.
     */
    function _checkAllSigned() private {
        // The owner is implicitly signed by creating the contract.
        if (tenantSigned && legalSigned) {
            state = AgreementState.Signed;
        }
    }

    /**
     * @dev Called by the Tenant to pay the security deposit into escrow.
     */
    function paySecurityDeposit() external payable onlyRole(tenant) inState(AgreementState.Signed) {
        require(msg.value == securityDeposit, "Incorrect security deposit amount.");
        state = AgreementState.Funded;
        emit DepositPaid(tenant, msg.value);
    }
    
    /**
     * @dev Allows owner or tenant to cancel the agreement before it is funded.
     * This is a safety exit if someone refuses to sign or pay.
     */
    function cancelAgreement() external inState(AgreementState.Created) {
        require(msg.sender == owner || msg.sender == tenant, "Only owner or tenant can cancel.");
        state = AgreementState.Cancelled;
        emit AgreementCancelled();
    }

    /**
     * @dev Called by the Owner to mark the lease as terminated after it ends.
     * This moves the contract to the deposit resolution phase.
     */
    function terminateLease() external onlyRole(owner) inState(AgreementState.Funded) onlyAfter(leaseEndDate) {
        state = AgreementState.Terminated;
        emit AgreementTerminated(block.timestamp);
    }

    /**
     * @dev Called by the Owner to propose how the deposit should be split.
     * @param _tenantShare Amount (in Wei) to return to the tenant.
     * @param _ownerShare Amount (in Wei) to give to the owner (for damages, etc.).
     */
    function proposeDepositSplit(
        uint _tenantShare,
        uint _ownerShare
    ) external onlyRole(owner) inState(AgreementState.Terminated) {
        require(
            _tenantShare + _ownerShare == securityDeposit,
            "Proposed split must equal the total deposit."
        );
        
        proposedTenantShare = _tenantShare;
        proposedOwnerShare = _ownerShare;
        ownerProposedSplit = true;
        
        emit SplitProposed(_tenantShare, _ownerShare);
    }

    /**
     * @dev Called by the Tenant to agree to the owner's proposed split.
     * This finalizes the agreement and disburses funds.
     */
    function agreeToSplit() external onlyRole(tenant) inState(AgreementState.Terminated) {
        require(ownerProposedSplit, "Owner has not proposed a split yet.");
        tenantAgreedToSplit = true;
        state = AgreementState.Completed;
        _disburseFunds(proposedTenantShare, proposedOwnerShare);
        emit SplitAgreed(proposedTenantShare, proposedOwnerShare);
    }
    
    /**
     * @dev Called by Owner or Tenant to raise a dispute.
     * This moves the contract to a state where only the legal professional can act.
     */
    function raiseDispute() external inState(AgreementState.Terminated) {
        require(msg.sender == owner || msg.sender == tenant, "Only owner or tenant can raise dispute.");
        // Can be raised even if a split is proposed but not agreed to.
        state = AgreementState.Disputed;
        emit DisputeRaised(msg.sender);
    }

    /**
     * @dev Called by the Legal Professional to resolve a dispute.
     * This is the final arbitration.
     * @param _tenantShare Amount (in Wei) to return to the tenant.
     * @param _ownerShare Amount (in Wei) to give to the owner.
     */
    function resolveDispute(
        uint _tenantShare,
        uint _ownerShare
    ) external onlyRole(legalProfessional) inState(AgreementState.Disputed) {
        require(
            _tenantShare + _ownerShare == securityDeposit,
            "Resolved split must equal the total deposit."
        );

        state = AgreementState.Completed;
        _disburseFunds(_tenantShare, _ownerShare);
        emit DisputeResolved(legalProfessional, _tenantShare, _ownerShare);
    }

    /**
     * @dev Internal function to send the funds to the parties.
     */
    function _disburseFunds(uint _tenantShare, uint _ownerShare) private {
        if (_tenantShare > 0) {
            (bool success, ) = payable(tenant).call{value: _tenantShare}("");
            if(success) emit FundsDisbursed(tenant, _tenantShare);
        }
        
        if (_ownerShare > 0) {
            (bool success, ) = payable(owner).call{value: _ownerShare}("");
            if(success) emit FundsDisbursed(owner, _ownerShare);
        }
    }
    
    /**
     * @dev Helper function to check the contract's balance.
     */
    function getContractBalance() public view returns (uint) {
        return address(this).balance;
    }
}

