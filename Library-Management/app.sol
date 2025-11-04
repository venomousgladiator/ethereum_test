// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title DecentralizedLibrary
 * @dev A smart contract for a library management system on the blockchain.
 * It allows a manager to add/remove books and users to borrow/return them.
 * It ensures transparency and role-based access control.
 */
contract DecentralizedLibrary {

    // --- State Variables ---

    address public immutable manager; // The address of the library manager
    uint public bookIdCounter;        // A counter to generate unique book IDs

    // --- Structs ---

    /**
     * @dev Defines the structure for a Book in the library.
     */
    struct Book {
        uint id;                 // Unique ID
        string title;
        string author;
        bool isAvailable;        // True if the book is in the library, false if borrowed
        address currentBorrower; // address(0) if available, or the borrower's address
    }

    // --- Mappings ---

    /**
     * @dev Maps a book ID to its Book struct.
     * This mapping is public, so Remix will auto-create a getter.
     */
    mapping(uint => Book) public books;

    // --- Events ---

    event BookAdded(uint indexed id, string title, string author, uint timestamp);
    event BookRemoved(uint indexed id, uint timestamp);
    event BookBorrowed(uint indexed id, address indexed borrower, uint timestamp);
    event BookReturned(uint indexed id, address indexed returner, uint timestamp);

    // --- Modifiers ---

    /**
     * @dev Restricts function access to the manager.
     */
    modifier onlyManager() {
        require(msg.sender == manager, "Only the manager can perform this action.");
        _;
    }

    // --- Constructor ---

    /**
     * @dev Sets the deployer of the contract as the manager.
     */
    constructor() {
        manager = msg.sender;
    }

    // --- Manager Functions ---

    /**
     * @dev Adds a new book to the library.
     * Only the manager can call this.
     * @param _title The title of the book.
     * @param _author The author of the book.
     */
    function addBook(string memory _title, string memory _author) public onlyManager {
        bookIdCounter++; // Increment first to start book IDs from 1
        
        books[bookIdCounter] = Book({
            id: bookIdCounter,
            title: _title,
            author: _author,
            isAvailable: true,
            currentBorrower: address(0)
        });

        emit BookAdded(bookIdCounter, _title, _author, block.timestamp);
    }

    /**
     * @dev Removes a book from the library.
     * Only the manager can call this.
     * The book must be available (not borrowed) to be removed.
     * @param _bookId The ID of the book to remove.
     */
    function removeBook(uint _bookId) public onlyManager {
        // Check if book exists
        require(books[_bookId].id != 0, "Book does not exist.");
        // Check if book is currently borrowed
        require(books[_bookId].isAvailable, "Book is currently borrowed, cannot remove.");
        
        // Delete the book entry
        delete books[_bookId];
        
        emit BookRemoved(_bookId, block.timestamp);
    }

    // --- User Functions ---

    /**
     * @dev Allows any user to borrow an available book.
     * @param _bookId The ID of the book to borrow.
     */
    function borrowBook(uint _bookId) public {
        Book storage book = books[_bookId];
        
        // Check if book exists
        require(book.id != 0, "Book does not exist.");
        // Check if book is available
        require(book.isAvailable, "Book is not available.");
        
        // Update book state
        book.isAvailable = false;
        book.currentBorrower = msg.sender;
        
        emit BookBorrowed(_bookId, msg.sender, block.timestamp);
    }

    /**
     * @dev Allows the *current borrower* to return a book.
     * @param _bookId The ID of the book to return.
     */
    function returnBook(uint _bookId) public {
        Book storage book = books[_bookId];

        // Check if book is actually borrowed
        require(!book.isAvailable, "Book is not currently borrowed.");
        // Check if the caller is the one who borrowed it
        require(book.currentBorrower == msg.sender, "Only the borrower can return this book.");
        
        // Update book state
        book.isAvailable = true;
        book.currentBorrower = address(0);
        
        emit BookReturned(_bookId, msg.sender, block.timestamp);
    }
}
