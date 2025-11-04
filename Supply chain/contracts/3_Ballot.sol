// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// We import OpenZeppelin's Ownable contract to manage ownership and permissions.
// This gives us a contract 'owner' who can add/remove stakeholders.
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.0/contracts/access/Ownable.sol";

/**
 * @title SupplyChain
 * @dev A smart contract to manage and track items through a supply chain.
 * It provides role-based access for different stakeholders (Producers,
 * Distributors, Retailers) and creates a verifiable, immutable history
 * for each item, enhancing transparency and traceability.
 */
contract SupplyChain is Ownable {
    
    // --- State Variables ---

    // Counter to generate unique item IDs (SKUs).
    // We start at 1, so 0 can represent a non-existent item.
    uint256 private _itemCounter;

    // Enum to represent the discrete states an item can be in.
    enum ItemState {
        Created,     // Item registered by a Producer
        Processed,   // Item modified by a Distributor/Producer
        InTransit,   // Item is being shipped
        Received,    // Item has been received by the next party
        ForSale,     // Item is in a retail location, ready for sale
        Sold         // Item has been sold to a consumer
    }

    // Struct to store a single event in an item's history.
    // This is the core of our traceability.
    struct HistoryEvent {
        uint256 timestamp;  // Time of the event (block.timestamp)
        address actor;      // Address that triggered the event
        ItemState newState; // The state the item was moved into
        string location;    // A string for location data (e.g., "Warehouse A", "GPS:...")
    }

    // Struct to represent a single item in the supply chain.
    struct Item {
        uint256 id;             // Unique ID
        string name;            // Name of the item (e.g., "Organic Coffee Batch #123")
        address currentOwner;   // Address of the stakeholder currently holding the item
        ItemState currentState; // The current state from the ItemState enum
        HistoryEvent[] history; // A dynamic array to store the item's full history
    }

    // Mapping to store all items, keyed by their unique ID.
    mapping(uint256 => Item) public items;

    // Mappings to manage stakeholder roles.
    // The contract owner will grant these roles.
    mapping(address => bool) public isProducer;
    mapping(address => bool) public isDistributor;
    mapping(address => bool) public isRetailer;

    // --- Events ---
    // Events are crucial for frontend applications to listen for changes.

    event RoleGranted(address indexed account, string role);
    event RoleRevoked(address indexed account, string role);
    event ItemCreated(uint256 indexed id, string name, address indexed producer);
    event ItemInTransit(uint256 indexed id, address indexed from, address indexed to, string location);
    event ItemReceived(uint256 indexed id, address indexed receiver, string location);
    event ItemProcessed(uint256 indexed id, address indexed processor, string location);
    event ItemForSale(uint256 indexed id, address indexed retailer, string location);
    event ItemSold(uint256 indexed id, address indexed consumer, string location);

    // --- Modifiers ---
    // Modifiers simplify access control for our functions.

    modifier onlyProducer() {
        require(isProducer[msg.sender], "Caller is not a producer");
        _;
    }

    modifier onlyDistributor() {
        require(isDistributor[msg.sender], "Caller is not a distributor");
        _;
    }

    modifier onlyRetailer() {
        require(isRetailer[msg.sender], "Caller is not a retailer");
        _;
    }

    modifier isOwnerOf(uint256 _id) {
        require(items[_id].currentOwner == msg.sender, "Caller is not the current owner");
        _;
    }

    modifier inState(uint256 _id, ItemState _state) {
        require(items[_id].currentState == _state, "Item is not in the required state");
        _;
    }

    // --- Constructor ---

    /**
     * @dev Sets the contract deployer as the initial owner and
     * initializes the item counter.
     */
    constructor() Ownable(msg.sender) {
        _itemCounter = 1; // Start IDs from 1
    }

    // --- Role Management Functions ---
    // Only the contract owner can add or remove stakeholders.

    function addProducer(address _account) public onlyOwner {
        isProducer[_account] = true;
        emit RoleGranted(_account, "Producer");
    }

    function removeProducer(address _account) public onlyOwner {
        isProducer[_account] = false;
        emit RoleRevoked(_account, "Producer");
    }

    function addDistributor(address _account) public onlyOwner {
        isDistributor[_account] = true;
        emit RoleGranted(_account, "Distributor");
    }

    function removeDistributor(address _account) public onlyOwner {
        isDistributor[_account] = false;
        emit RoleRevoked(_account, "Distributor");
    }

    function addRetailer(address _account) public onlyOwner {
        isRetailer[_account] = true;
        emit RoleGranted(_account, "Retailer");
    }

    function removeRetailer(address _account) public onlyOwner {
        isRetailer[_account] = false;
        emit RoleRevoked(_account, "Retailer");
    }

    // --- Core Logic Functions ---

    /**
     * @dev Creates a new item and registers it on the blockchain.
     * Can only be called by an approved Producer.
     * @param _name Name of the item.
     * @param _initialLocation Location where the item is created.
     */
    function createItem(string memory _name, string memory _initialLocation) public onlyProducer {
        uint256 newItemId = _itemCounter;
        
        // Create the initial history event
        HistoryEvent memory initialEvent = HistoryEvent({
            timestamp: block.timestamp,
            actor: msg.sender,
            newState: ItemState.Created,
            location: _initialLocation
        });

        // Create the new item
        Item storage newItem = items[newItemId];
        newItem.id = newItemId;
        newItem.name = _name;
        newItem.currentOwner = msg.sender; // The producer is the first owner
        newItem.currentState = ItemState.Created;
        newItem.history.push(initialEvent);

        _itemCounter++;
        emit ItemCreated(newItemId, _name, msg.sender);
    }

    /**
     * @dev Ships an item to the next stakeholder (e.g., Producer to Distributor).
     * This transfers "ownership" in the DApp to the recipient.
     * @param _id The ID of the item to ship.
     * @param _recipient The address of the next stakeholder.
     * @param _location The location from which the item is being shipped.
     */
    function shipItem(uint256 _id, address _recipient, string memory _location)
        public
        isOwnerOf(_id) // Only the current owner can ship it
    {
        // Ensure the item is in a shippable state
        require(
            items[_id].currentState == ItemState.Created ||
            items[_id].currentState == ItemState.Processed ||
            items[_id].currentState == ItemState.Received,
            "Item cannot be shipped from its current state"
        );
        
        // Ensure recipient is a valid stakeholder
        require(
            isDistributor[_recipient] || isRetailer[_recipient],
            "Recipient is not a valid distributor or retailer"
        );

        // Update item state
        items[_id].currentOwner = _recipient;
        items[_id].currentState = ItemState.InTransit;
        
        _logHistory(_id, ItemState.InTransit, _location);
        emit ItemInTransit(_id, msg.sender, _recipient, _location);
    }

    /**
     * @dev Confirms receiving an item.
     * Can be called by a Distributor or Retailer.
     * @param _id The ID of the item.
     * @param _location The location where the item was received.
     */
    function receiveItem(uint256 _id, string memory _location)
        public
        isOwnerOf(_id) // Only the new owner (recipient) can confirm receipt
        inState(_id, ItemState.InTransit) // Must be in transit
    {
        require(
            isDistributor[msg.sender] || isRetailer[msg.sender],
            "Caller is not a distributor or retailer"
        );
        
        items[_id].currentState = ItemState.Received;
        _logHistory(_id, ItemState.Received, _location);
        emit ItemReceived(_id, msg.sender, _location);
    }

    /**
     * @dev A distributor processes an item (e.g., roasting coffee).
     * @param _id The ID of the item.
     * @param _location The location where processing occurs.
     */
    function processItem(uint256 _id, string memory _location)
        public
        onlyDistributor
        isOwnerOf(_id)
        inState(_id, ItemState.Received) // Must be received to be processed
    {
        items[_id].currentState = ItemState.Processed;
        _logHistory(_id, ItemState.Processed, _location);
        emit ItemProcessed(_id, msg.sender, _location);
    }

    /**
     * @dev A retailer marks an item as available for sale.
     * @param _id The ID of the item.
     * @param _location The retail location.
     */
    function markForSale(uint256 _id, string memory _location)
        public
        onlyRetailer
        isOwnerOf(_id)
        inState(_id, ItemState.Received) // Must be received by retailer
    {
        items[_id].currentState = ItemState.ForSale;
        _logHistory(_id, ItemState.ForSale, _location);
        emit ItemForSale(_id, msg.sender, _location);
    }

    /**
     * @dev Marks an item as "Sold" and transfers ownership to the end consumer.
     * @param _id The ID of the item.
     * @param _consumer The address of the consumer.
     * @param _location The point-of-sale location.
     */
    function markSold(uint256 _id, address _consumer, string memory _location)
        public
        onlyRetailer
        isOwnerOf(_id)
        inState(_id, ItemState.ForSale) // Must be for sale
    {
        items[_id].currentState = ItemState.Sold;
        items[_id].currentOwner = _consumer; // Final owner
        
        _logHistory(_id, ItemState.Sold, _location);
        emit ItemSold(_id, _consumer, _location);
    }

    // --- Helper Functions ---

    /**
     * @dev Internal helper function to create and store a new history event.
     */
    function _logHistory(uint256 _id, ItemState _newState, string memory _location) internal {
        items[_id].history.push(HistoryEvent({
            timestamp: block.timestamp,
            actor: msg.sender,
            newState: _newState,
            location: _location
        }));
    }

    // --- View Functions ---
    // These functions read data from the contract and do not cost gas (when called externally).

    /**
     * @dev Returns a high-level summary of an item.
     * @param _id The ID of the item.
     * @return id The item's ID.
     * @return name The item's name.
     * @return currentOwner The item's current owner.
     * @return currentState The item's current ItemState.
     */
    function getItemSummary(uint256 _id)
        public
        view
        returns (
            uint256 id,
            string memory name,
            address currentOwner,
            ItemState currentState
        )
    {
        Item storage item = items[_id];
        return (item.id, item.name, item.currentOwner, item.currentState);
    }

    /**
     * @dev Returns the full, immutable history of an item.
     * @param _id The ID of the item.
     * @return The array of HistoryEvent structs.
     */
    function getItemHistory(uint256 _id)
        public
        view
        returns (HistoryEvent[] memory)
    {
        return items[_id].history;
    }
}