// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title EventRSVP
 * @dev A decentralized system for managing event RSVPs and check-ins.
 * This contract is designed for a test environment and CLI interaction.
 *
 * Workflow (for CLI):
 * 1. Organizer deploys `EventRSVP.sol`.
 * 2. Organizer calls `createEvent()` with a name, fee (in Wei), and capacity.
 * - This emits `EventCreated` with a new `eventId` (which is the array index).
 * 3. Attendees find the `eventId` and `rsvpFee`.
 * 4. Attendees call `rsvp(eventId)` and send the exact `rsvpFee` as `msg.value`.
 * - This emits `RSVPd`.
 * 5. On event day, the Organizer uses the attendee's address to call `checkIn(eventId, attendeeAddress)`.
 * - This emits `CheckedIn`.
 * 6. After the event, the Organizer can call `closeEvent(eventId)` to stop new RSVPs.
 * 7. The Organizer can call `withdrawFees(eventId)` at any time to collect the funds.
 */
contract EventRSVP {

    // --- Structs & Enums ---

    /**
     * @dev Defines the current state of an event.
     */
    enum EventState {
        Open,  // Accepting RSVPs
        Closed // Not accepting RSVPs (e.g., event is over)
    }

    /**
     * @dev Stores the status of a single attendee for a specific event.
     */
    struct AttendeeStatus {
        bool rsvpd;     // True if they paid and are on the list
        bool checkedIn; // True if the organizer has checked them in
    }

    /**
     * @dev Stores all data for a single event.
     */
    struct Event {
        address payable organizer; // The event creator
        string name;               // Name of the event
        uint rsvpFee;              // Cost to RSVP (in Wei)
        uint capacity;             // Max number of attendees
        uint rsvpdCount;           // Current number of RSVPs
        uint checkedInCount;       // Current number of checked-in attendees
        EventState state;          // Open or Closed
        uint creationTime;         // Timestamp of event creation
    }

    // --- State Variables ---

    /**
     * @dev An array of all events created through this contract.
     * The array index is the `eventId`.
     */
    Event[] public events;

    /**
     * @dev Nested mapping to track attendee status: eventId -> attendeeAddress -> Status
     * This provides a tamper-proof record of who RSVP'd and who checked in.
     */
    mapping(uint => mapping(address => AttendeeStatus)) public attendeeStatus;

    /**
     * @dev Tracks the balance of collected fees for each event.
     * This is crucial so one organizer's funds are not mixed with another's.
     */
    mapping(uint => uint) public eventBalances;

    // --- Events ---

    event EventCreated(
        uint indexed eventId,
        address indexed organizer,
        string name,
        uint rsvpFee,
        uint capacity
    );

    event RSVPd(uint indexed eventId, address indexed attendee, uint feePaid);
    event CheckedIn(uint indexed eventId, address indexed attendee);
    event EventClosed(uint indexed eventId);
    event FeesWithdrawn(uint indexed eventId, uint amount);

    // --- Modifiers ---

    /**
     * @dev Ensures that only the organizer of a specific event can call a function.
     */
    modifier onlyOrganizer(uint _eventId) {
        require(_eventId < events.length, "Invalid event ID.");
        require(
            msg.sender == events[_eventId].organizer,
            "Only the event organizer can call this."
        );
        _;
    }

    // --- Functions ---

    /**
     * @dev Creates a new event, making the caller the organizer.
     * @param _name The public name of the event.
     * @param _rsvpFee The cost in Wei to RSVP.
     * @param _capacity The maximum number of attendees.
     */
    function createEvent(
        string calldata _name,
        uint _rsvpFee,
        uint _capacity
    ) public {
        require(_rsvpFee > 0, "RSVP fee must be greater than zero.");
        require(_capacity > 0, "Capacity must be greater than zero.");

        Event memory newEvent;
        newEvent.organizer = payable(msg.sender);
        newEvent.name = _name;
        newEvent.rsvpFee = _rsvpFee;
        newEvent.capacity = _capacity;
        newEvent.rsvpdCount = 0;
        newEvent.checkedInCount = 0;
        newEvent.state = EventState.Open;
        newEvent.creationTime = block.timestamp;

        // Add the new event to the array. The `eventId` is the new length - 1.
        events.push(newEvent);
        uint eventId = events.length - 1;

        emit EventCreated(eventId, msg.sender, _name, _rsvpFee, _capacity);
    }

    /**
     * @dev Allows an attendee to RSVP for an event by paying the fee.
     * @param _eventId The ID of the event to RSVP for.
     */
    function rsvp(uint _eventId) public payable {
        require(_eventId < events.length, "Invalid event ID.");

        Event storage e = events[_eventId];
        AttendeeStatus storage status = attendeeStatus[_eventId][msg.sender];

        // 1. Check conditions
        require(e.state == EventState.Open, "Event is not open for RSVPs.");
        require(msg.value == e.rsvpFee, "Incorrect RSVP fee paid.");
        require(e.rsvpdCount < e.capacity, "Event is at full capacity.");
        require(!status.rsvpd, "You have already RSVP'd.");

        // 2. Update state
        status.rsvpd = true;
        status.checkedIn = false; // Explicitly set
        e.rsvpdCount++;
        eventBalances[_eventId] += msg.value;

        // 3. Emit log
        emit RSVPd(_eventId, msg.sender, msg.value);
    }

    /**
     * @dev Allows the organizer to check in an attendee on event day.
     * This creates the tamper-proof record of attendance.
     * @param _eventId The ID of the event.
     * @param _attendee The address of the attendee to check in.
     */
    function checkIn(uint _eventId, address _attendee) public onlyOrganizer(_eventId) {
        AttendeeStatus storage status = attendeeStatus[_eventId][_attendee];
        Event storage e = events[_eventId];

        // 1. Check conditions
        require(status.rsvpd, "This address has not RSVP'd.");
        require(!status.checkedIn, "This attendee is already checked in.");

        // 2. Update state
        status.checkedIn = true;
        e.checkedInCount++;

        // 3. Emit log
        emit CheckedIn(_eventId, _attendee);
    }

    /**
     * @dev Allows the organizer to close an event to new RSVPs.
     * @param _eventId The ID of the event.
     */
    function closeEvent(uint _eventId) public onlyOrganizer(_eventId) {
        Event storage e = events[_eventId];
        require(e.state == EventState.Open, "Event is already closed.");

        e.state = EventState.Closed;
        emit EventClosed(_eventId);
    }

    /**
     * @dev Allows the organizer to withdraw all collected fees for their event.
     * @param _eventId The ID of the event.
     */
    function withdrawFees(uint _eventId) public onlyOrganizer(_eventId) {
        uint balance = eventBalances[_eventId];
        require(balance > 0, "No fees to withdraw.");

        // Re-entrancy guard: set balance to 0 *before* sending.
        eventBalances[_eventId] = 0;

        (bool sent, ) = msg.sender.call{value: balance}("");
        require(sent, "Fee withdrawal failed.");

        emit FeesWithdrawn(_eventId, balance);
    }

    // --- View Functions (Helpers for CLI) ---

    /**
     * @dev Returns the total number of events created.
     */
    function getEventCount() public view returns (uint) {
        return events.length;
    }

    /**
     * @dev Returns details for a specific event.
     */
    function getEventDetails(uint _eventId)
        public
        view
        returns (
            address organizer,
            string memory name,
            uint rsvpFee,
            uint capacity,
            uint rsvpdCount,
            uint checkedInCount,
            EventState state,
            uint balance
        )
    {
        require(_eventId < events.length, "Invalid event ID.");
        Event storage e = events[_eventId];
        return (
            e.organizer,
            e.name,
            e.rsvpFee,
            e.capacity,
            e.rsvpdCount,
            e.checkedInCount,
            e.state,
            eventBalances[_eventId]
        );
    }

    /**
     * @dev Returns the RSVP and check-in status for a specific attendee.
     */
    function getAttendeeStatus(uint _eventId, address _attendee)
        public
        view
        returns (bool rsvpd, bool checkedIn)
    {
        // No event ID check needed; if no entry exists, it will return (false, false)
        AttendeeStatus storage status = attendeeStatus[_eventId][_attendee];
        return (status.rsvpd, status.checkedIn);
    }
}
