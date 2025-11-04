// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title TodoList
 * @dev A simple, decentralized To-Do list application.
 * Each user address has its own private list of tasks.
 */
contract TodoList {

    // --- Task Struct ---
    // Defines the data structure for a single task.
    struct Task {
        string content;
        bool completed;
    }

    // --- Storage ---
    // A mapping from each user's address to their personal array of tasks.
    // This ensures data ownership; only you can access and modify your list.
    mapping(address => Task[]) public tasks;

    // --- Events ---
    // Emitted when a new task is created.
    event TaskCreated(address indexed user, uint id, string content);
    // Emitted when a task's completion status is toggled.
    event TaskToggled(address indexed user, uint id, bool completed);
    // Emitted when a task is deleted.
    event TaskDeleted(address indexed user, uint id);


    // --- Functions ---

    /**
     * @dev Creates a new task and adds it to the caller's list.
     * @param _content The text content of the task.
     */
    function createTask(string memory _content) public {
        // Adds a new Task struct to the end of the msg.sender's task array.
        tasks[msg.sender].push(Task(_content, false));
        
        // Get the ID (index) of the newly created task.
        uint id = tasks[msg.sender].length - 1;
        
        emit TaskCreated(msg.sender, id, _content);
    }

    /**
     * @dev Toggles the completion status of one of the caller's tasks.
     * @param _id The ID (index) of the task to toggle.
     */
    function toggleCompleted(uint _id) public {
        // Require that the task ID is valid (within the bounds of the user's array).
        require(_id < tasks[msg.sender].length, "Task does not exist");

        // Get a reference to the task in storage.
        Task storage task = tasks[msg.sender][_id];
        
        // Toggle the completed status.
        task.completed = !task.completed;
        
        emit TaskToggled(msg.sender, _id, task.completed);
    }

    /**
     * @dev Deletes one of the caller's tasks.
     * Uses the "move-and-pop" pattern for gas efficiency.
     * @param _id The ID (index) of the task to delete.
     */
    function deleteTask(uint _id) public {
        require(_id < tasks[msg.sender].length, "Task does not exist");

        // --- Solidity Array Deletion Pattern ---
        // This is the most gas-efficient way to delete from an array.
        
        // 1. Move the *last* task in the array to the position of the one
        //    we want to delete.
        tasks[msg.sender][_id] = tasks[msg.sender][tasks[msg.sender].length - 1];
        
        // 2. Remove the (now duplicated) last element.
        tasks[msg.sender].pop();
        
        // Note: This pattern has one side-effect: the ID (index) of the
        // task that was previously last in the list has now changed.
        // This is a standard trade-off for efficiency in Solidity.
        
        emit TaskDeleted(msg.sender, _id);
    }


    // --- View Functions ---

    /**
     * @dev Returns the caller's entire list of tasks.
     * This is a 'view' function, so it's free to call.
     */
    function getTasks() public view returns (Task[] memory) {
        return tasks[msg.sender];
    }
    
    /**
     * @dev Returns the total number of tasks for the caller.
     */
    function getTaskCount() public view returns (uint) {
        return tasks[msg.sender].length;
    }
}
