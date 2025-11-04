// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title SupplyChain
 * @dev A smart contract for tracking items through a multi-stage supply chain.
 * This contract implements Role-Based Access Control (RBAC) to manage permissions
 * for different stakeholders (Harvester, Processor, Distributor, Retailer, Consumer).
 *
 * Workflow:
 * 1. Deployer (Owner) grants roles (e.g., HARVESTER_ROLE) to stakeholder addresses.
 * 2. Harvester calls `harvestItem()` to create a new item on the blockchain.
 * 3. Processor calls `processItem()`, transferring ownership and updating its state.
 * 4. Distributor calls `packItem()`.
 * 5. Retailer calls `receiveItem()`.
 * 6. Retailer calls `sellItem()`, transferring final ownership to a consumer.
 *
 * At any point, anyone can call `getItem()` and `getItemHistory()` to trace
 * the item's full, immutable history.
 */
contract SupplyChain {

    // --- State Variables ---

    address public owner; // The contract deployer, responsible for role management
    uint public nextItemId; // Counter to ensure unique item IDs

    // --- Roles ---
    // We define roles as bytes32 hashes for efficient storage and checking
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");
    bytes32 public constant PROCESSOR_ROLE = keccak256("PROCESSOR_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant RETAILER_ROLE = keccak256("RETAILER_ROLE");
    bytes32 public constant CONSUMER_ROLE = keccak256("CONSUMER_ROLE");

    // Mapping: role -> account -> hasRole?
    mapping(bytes32 => mapping(address => bool)) public roles;

    // --- Data Structures ---

    /**
     * @dev The current state of an item in the supply chain.
     */
    enum ItemState {
        Harvested,  // 0
        Processed,  // 1
        Packed,     // 2
        ForSale,    // 3
        Sold        // 4
    }

    /**
     * @dev The core data structure for a traceable item.
     */
    struct Item {
        string name;         // A human-readable name, e.g., "Batch 42 Organic Coffee"
        uint id;             // The unique item ID
        address currentOwner; // The address of the stakeholder currently holding the item
        ItemState state;     // The current stage of the item
    }

    // Mapping: itemId -> Item
    mapping(uint => Item) public items;

    /**
     * @dev A single entry in an item's history log.
     */
    struct HistoryEntry {
        uint timestamp;      // Time of the action
        ItemState state;     // The new state of the item
        address actor;       // The stakeholder who performed the action
        string message;      // A description of the action
    }

    // Mapping: itemId -> Array of HistoryEntry
    // This provides the full traceability.
    mapping(uint => HistoryEntry[]) public itemHistory;

    // --- Events ---

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed admin);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed admin);
    event ItemStateChanged(
        uint indexed itemId,
        address indexed actor,
        ItemState newState,
        string message
    );

    // --- Modifiers ---

    /**
     * @dev Restricts function access to the contract owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this.");
        _;
    }

    /**
     * @dev Restricts function access to stakeholders with a specific role.
     */
    modifier onlyRole(bytes32 _role) {
        require(roles[_role][msg.sender], "Caller does not have the required role.");
        _;
    }

    /**
     * @dev Checks that an item is in the required state before proceeding.
     */
    modifier inState(uint _itemId, ItemState _state) {
        require(items[_itemId].state == _state, "Item is not in the required state.");
        _;
    }

    // --- Constructor ---

    constructor() {
        owner = msg.sender;
        emit RoleGranted(keccak256("OWNER"), msg.sender, msg.sender);
    }

    // --- Role Management Functions (Owner Only) ---

    /**
     * @dev Grants a role to a specific account.
     * @param _role The role to grant (e.g., HARVESTER_ROLE).
     * @param _account The address of the stakeholder.
     */
    function grantRole(bytes32 _role, address _account) public onlyOwner {
        require(_account != address(0), "Invalid address.");
        roles[_role][_account] = true;
        emit RoleGranted(_role, _account, msg.sender);
    }

    /**
     * @dev Revokes a role from a specific account.
     * @param _role The role to revoke.
     * @param _account The address of the stakeholder.
     */
    function revokeRole(bytes32 _role, address _account) public onlyOwner {
        require(_account != address(0), "Invalid address.");
        roles[_role][_account] = false;
        emit RoleRevoked(_role, _account, msg.sender);
    }

    /**
     * @dev Helper to check if an account has a role.
     */
    function hasRole(bytes32 _role, address _account) public view returns (bool) {
        return roles[_role][_account];
    }

    // --- Core Supply Chain Functions (Role-Restricted) ---

    /**
     * @dev Creates a new item (e.g., harvesting).
     * Only callable by an account with the HARVESTER_ROLE.
     * @param _name The name of the new item.
     */
    function harvestItem(string memory _name) public onlyRole(HARVESTER_ROLE) {
        uint itemId = nextItemId;
        
        items[itemId] = Item(_name, itemId, msg.sender, ItemState.Harvested);
        
        _addHistory(itemId, "Item harvested.", ItemState.Harvested);
        
        nextItemId++;
    }

    /**
     * @dev Processes an item (e.g., roasting coffee).
     * Only callable by a PROCESSOR_ROLE.
     */
    function processItem(uint _itemId) public onlyRole(PROCESSOR_ROLE) inState(_itemId, ItemState.Harvested) {
        _updateItem(_itemId, ItemState.Processed, "Item processed.");
    }

    /**
     * @dev Packs an item for shipment.
     * Only callable by a DISTRIBUTOR_ROLE.
     */
    function packItem(uint _itemId) public onlyRole(DISTRIBUTOR_ROLE) inState(_itemId, ItemState.Processed) {
        _updateItem(_itemId, ItemState.Packed, "Item packed for shipment.");
    }

    /**
     * @dev Marks an item as received by a retailer and available for sale.
     * Only callable by a RETAILER_ROLE.
     */
    function receiveItem(uint _itemId) public onlyRole(RETAILER_ROLE) inState(_itemId, ItemState.Packed) {
        _updateItem(_itemId, ItemState.ForSale, "Item received by retailer.");
    }

    /**
     * @dev Sells an item to a consumer.
     * Only callable by a RETAILER_ROLE.
     * @param _consumerAddress The address of the final consumer.
     */
    function sellItem(uint _itemId, address _consumerAddress) public onlyRole(RETAILER_ROLE) inState(_itemId, ItemState.ForSale) {
        require(_consumerAddress != address(0), "Invalid consumer address.");
        
        // Grant consumer role automatically
        if (!roles[CONSUMER_ROLE][_consumerAddress]) {
            roles[CONSUMER_ROLE][_consumerAddress] = true;
            emit RoleGranted(CONSUMER_ROLE, _consumerAddress, msg.sender);
        }

        Item storage item = items[_itemId];
        item.state = ItemState.Sold;
        item.currentOwner = _consumerAddress; // Final ownership transfer

        // Note: The 'actor' is the retailer (msg.sender) who sold it.
        _addHistory(_itemId, "Item sold to consumer.", ItemState.Sold);
    }

    // --- Internal Helper Functions ---

    /**
     * @dev Internal function to add a history entry and emit an event.
     */
    function _addHistory(uint _itemId, string memory _message, ItemState _newState) internal {
        itemHistory[_itemId].push(HistoryEntry({
            timestamp: block.timestamp,
            state: _newState,
            actor: msg.sender,
            message: _message
        }));

        emit ItemStateChanged(_itemId, msg.sender, _newState, _message);
    }

    /**
     * @dev Internal helper to update an item's state and owner, and add history.
     */
    function _updateItem(uint _itemId, ItemState _newState, string memory _message) internal {
        Item storage item = items[_itemId];
        item.state = _newState;
        item.currentOwner = msg.sender; // Transfer custody to the actor
        
        _addHistory(_itemId, _message, _newState);
    }

    // --- View Functions (Public Data Access) ---

    /**
     * @dev Fetches the current details of a specific item.
     */
    function getItem(uint _itemId) public view returns (
        string memory name,
        uint id,
        address currentOwner,
        ItemState state
    ) {
        require(_itemId < nextItemId, "Item does not exist.");
        Item storage item = items[_itemId];
        return (
            item.name,
            item.id,
            item.currentOwner,
            item.state
        );
    }

    /**
     * @dev Fetches the complete history of an item for full traceability.
     */
    function getItemHistory(uint _itemId) public view returns (HistoryEntry[] memory) {
        require(_itemId < nextItemId, "Item does not exist.");
        return itemHistory[_itemId];
    }
}
