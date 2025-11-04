// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// We use OpenZeppelin's 'Ownable' to manage who can set the arbitrator.
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RentalAgreement
 * @dev A smart contract to manage rental agreements, signatures, and
 * security deposit escrow between an owner, a tenant, and an arbitrator.
 */
contract RentalAgreement is Ownable {

    // --- State ---

    enum AgreementState {
        Pending,   // Agreement created, awaiting tenant signature and deposit
        Active,    // Signed by both, deposit paid, lease is active
        Terminated, // Lease period is over and deposit has been released
        Disputed   // A dispute has been raised, awaiting arbitrator
    }

    struct Agreement {
        uint256 id;
        address owner;
        address tenant;
        string propertyAddress;  // For description, e.g., "123 Main St"
        uint256 rentAmount;      // Rent per period (in wei)
        uint256 securityDeposit; // Security deposit (in wei), held by contract
        uint256 leaseEndDate;    // Unix timestamp of lease end
        bool ownerSigned;
        bool tenantSigned;
        bool depositPaid;
        AgreementState state;
    }

    // --- State Variables ---

    address public arbitrator;
    uint256 private nextAgreementId = 1;

    mapping(uint256 => Agreement) public agreements;

    // --- Modifiers ---

    modifier onlyArbitrator() {
        require(msg.sender == arbitrator, "Caller is not the arbitrator");
        _;
    }

    modifier onlyAgreementParty(uint256 _id) {
        require(msg.sender == agreements[_id].owner || msg.sender == agreements[_id].tenant, "Caller is not a party to this agreement");
        _;
    }

    // --- Events ---

    event ArbitratorSet(address indexed arbitrator);
    event AgreementCreated(uint256 indexed id, address indexed owner, address indexed tenant);
    event AgreementSigned(uint256 indexed id, address indexed signer);
    event DepositPaid(uint256 indexed id, uint256 amount);
    event AgreementActivated(uint256 indexed id);
    event AgreementTerminated(uint256 indexed id);
    event AgreementDisputed(uint256 indexed id);
    event DepositReleased(uint256 indexed id, address indexed recipient, uint256 amount);

    // --- Functions ---

    /**
     * @dev Sets the arbitrator. Only the contract owner (deployer) can do this.
     * @param _arbitrator The address of the legal professional.
     */
    constructor(address _arbitrator) Ownable(msg.sender) { // <-- FIX HERE
        setArbitrator(_arbitrator);
    }

    function setArbitrator(address _arbitrator) public onlyOwner {
        require(_arbitrator != address(0), "Cannot set arbitrator to zero address");
        arbitrator = _arbitrator;
        emit ArbitratorSet(_arbitrator);
    }

    /**
     * @dev Owner creates a new agreement.
     * @param _tenant The address of the tenant.
     * @param _propertyAddress A string describing the property.
     * @param _rentAmount The rent amount in wei.
     * @param _securityDeposit The security deposit in wei.
     * @param _leaseEndDate The Unix timestamp for when the lease ends.
     */
    function createAgreement(
        address _tenant,
        string memory _propertyAddress,
        uint256 _rentAmount,
        uint256 _securityDeposit,
        uint256 _leaseEndDate
    ) public {
        require(_tenant != address(0), "Tenant cannot be zero address");
        require(_leaseEndDate > block.timestamp, "Lease end date must be in the future");
        
        uint256 id = nextAgreementId++;
        agreements[id] = Agreement({
            id: id,
            owner: msg.sender,
            tenant: _tenant,
            propertyAddress: _propertyAddress,
            rentAmount: _rentAmount,
            securityDeposit: _securityDeposit,
            leaseEndDate: _leaseEndDate,
            ownerSigned: true, // Owner signs upon creation
            tenantSigned: false,
            depositPaid: false,
            state: AgreementState.Pending
        });

        emit AgreementCreated(id, msg.sender, _tenant);
        emit AgreementSigned(id, msg.sender);
    }

    /**
     * @dev Called by the tenant to sign their side of the agreement.
     */
    function signAgreement_Tenant(uint256 _id) public {
        Agreement storage agreement = agreements[_id];
        require(msg.sender == agreement.tenant, "Only the tenant can sign");
        require(agreement.state == AgreementState.Pending, "Agreement is not pending");
        require(!agreement.tenantSigned, "Tenant has already signed");

        agreement.tenantSigned = true;
        emit AgreementSigned(_id, msg.sender);
    }

    /**
     * @dev Tenant pays the security deposit. This activates the agreement.
     * This function is 'payable' and holds the ETH in the contract.
     */
    function paySecurityDeposit(uint256 _id) public payable {
        Agreement storage agreement = agreements[_id];
        require(msg.sender == agreement.tenant, "Only the tenant can pay the deposit");
        require(agreement.state == AgreementState.Pending, "Agreement is not pending");
        require(agreement.ownerSigned && agreement.tenantSigned, "Both parties must sign first");
        require(msg.value == agreement.securityDeposit, "Must pay the exact deposit amount");

        agreement.depositPaid = true;
        agreement.state = AgreementState.Active;

        emit DepositPaid(_id, msg.value);
        emit AgreementActivated(_id);
    }

    /**
     * @dev At the end of the lease, either party can call this to terminate.
     * If the lease end date has passed, deposit is returned to tenant.
     * If called early, it automatically triggers a dispute.
     */
    function terminateAgreement(uint256 _id) public onlyAgreementParty(_id) {
        Agreement storage agreement = agreements[_id];
        require(agreement.state == AgreementState.Active, "Agreement must be active");

        if (block.timestamp >= agreement.leaseEndDate) {
            // Lease has ended normally. Return deposit to tenant.
            agreement.state = AgreementState.Terminated;
            agreement.depositPaid = false; // Mark as returned
            
            // Transfer deposit back to tenant
            (bool success, ) = agreement.tenant.call{value: agreement.securityDeposit}("");
            require(success, "Deposit transfer failed");

            emit DepositReleased(_id, agreement.tenant, agreement.securityDeposit);
            emit AgreementTerminated(_id);

        } else {
            // Lease is terminated early. This automatically raises a dispute
            // for the arbitrator to handle the deposit.
            agreement.state = AgreementState.Disputed;
            emit AgreementDisputed(_id);
        }
    }

    /**
     * @dev Either party can raise a dispute during an active lease.
     */
    function raiseDispute(uint256 _id) public onlyAgreementParty(_id) {
        Agreement storage agreement = agreements[_id];
        require(agreement.state == AgreementState.Active, "Agreement must be active to dispute");
        
        agreement.state = AgreementState.Disputed;
        emit AgreementDisputed(_id);
    }

    /**
     * @dev The arbitrator resolves a dispute and splits the deposit.
     * @param _id The agreement ID.
     * @param _tenantAmount The amount (in wei) to release to the tenant.
     * @param _ownerAmount The amount (in wei) to release to the owner.
     */
    function resolveDispute(uint256 _id, uint256 _tenantAmount, uint256 _ownerAmount) public onlyArbitrator {
        Agreement storage agreement = agreements[_id];
        require(agreement.state == AgreementState.Disputed, "Agreement is not in dispute");
        require(_tenantAmount + _ownerAmount == agreement.securityDeposit, "Split amounts must equal total deposit");

        agreement.state = AgreementState.Terminated;
        agreement.depositPaid = false; // Mark as handled

        if (_tenantAmount > 0) {
            (bool success, ) = agreement.tenant.call{value: _tenantAmount}("");
            require(success, "Tenant transfer failed");
            emit DepositReleased(_id, agreement.tenant, _tenantAmount);
        }
        if (_ownerAmount > 0) {
            (bool success, ) = agreement.owner.call{value: _ownerAmount}("");
            require(success, "Owner transfer failed");
            emit DepositReleased(_id, agreement.owner, _ownerAmount);
        }
        
        emit AgreementTerminated(_id);
    }

    // --- View Functions ---

    /**
     * @dev Gets all details for a specific agreement.
     */
    function getAgreement(uint256 _id) public view returns (Agreement memory) {
        return agreements[_id];
    }

    /**
     * @dev Returns the total amount of ETH held in escrow by this contract.
     */
    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }
}