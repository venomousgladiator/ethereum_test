// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title DocumentNotary
 * @dev A smart contract to notarize documents by storing their hashes.
 * This contract creates an immutable, timestamped proof of a document's
 * existence at a specific point in time.
 *
 * Workflow:
 * 1. A user generates a unique hash (e.g., SHA-256) of a document OFF-CHAIN.
 * 2. The user calls `notarizeDocument()`, passing in that `bytes32` hash
 * and a human-readable name for the document.
 * 3. The contract stores the hash, the sender's address (owner), and the
 * block timestamp.
 * 4. Anyone can later call `verifyDocument()` with the hash to prove
 * its existence and see who registered it and when.
 */
contract DocumentNotary {

    // --- Data Structures ---

    /**
     * @dev Stores the details of a notarized document hash.
     */
    struct Notarization {
        address owner;      // The address that registered this hash
        uint timestamp;     // The block timestamp when it was registered
        string documentName;  // A human-readable name for the document
        bool exists;        // A flag to confirm this hash has been registered
    }

    // --- State Variables ---

    /**
     * @dev Mapping from a document's hash (bytes32) to its notarization details.
     * This is the core ledger of notarized documents.
     */
    mapping(bytes32 => Notarization) public notarizations;

    // --- Events ---

    /**
     * @dev Emitted when a new document hash is successfully notarized.
     */
    event DocumentNotarized(
        address indexed owner,
        bytes32 indexed documentHash,
        uint timestamp,
        string documentName
    );

    // --- Functions ---

    /**
     * @dev Notarizes a document by storing its hash on the blockchain.
     * @param _documentHash The unique hash (e.g., SHA-256) of the document.
     * @param _documentName A name to associate with the document (e.g., "Contract_V1.pdf").
     */
    function notarizeDocument(bytes32 _documentHash, string memory _documentName) public {
        // 1. Check: Ensure this hash has not been notarized already.
        require(
            !notarizations[_documentHash].exists,
            "This document hash is already notarized."
        );

        // 2. Check: Ensure the hash is not empty.
        require(_documentHash != 0, "Document hash cannot be empty.");

        // 3. Store: Create the new notarization record.
        notarizations[_documentHash] = Notarization({
            owner: msg.sender,
            timestamp: block.timestamp,
            documentName: _documentName,
            exists: true
        });

        // 4. Emit: Announce the new notarization.
        emit DocumentNotarized(
            msg.sender,
            _documentHash,
            block.timestamp,
            _documentName
        );
    }

    // --- View Functions ---

    /**
     * @dev Verifies a document's notarization details by its hash.
     * @param _documentHash The hash of the document to check.
     * @return owner The address that notarized the document.
     * @return timestamp The Unix timestamp when it was notarized.
     * @return documentName The name given to the document.
     * @return exists True if the hash has been notarized.
     */
    function verifyDocument(bytes32 _documentHash)
        public
        view
        returns (
            address owner,
            uint timestamp,
            string memory documentName,
            bool exists
        )
    {
        Notarization storage n = notarizations[_documentHash];
        return (n.owner, n.timestamp, n.documentName, n.exists);
    }

    /**
     * @dev A simple helper to check if a hash exists in the system.
     * @param _documentHash The hash of the document to check.
     * @return True if the hash has been notarized, false otherwise.
     */
    function doesHashExist(bytes32 _documentHash) public view returns (bool) {
        return notarizations[_documentHash].exists;
    }
}
