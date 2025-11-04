// --- 1. CONFIGURATION: UPDATE THESE VALUES ---

// The address of your deployed SupplyChain contract.
// Get this after you deploy in Remix or on a testnet.
const CONTRACT_ADDRESS = "0xd9145CCE52D386f254917e481eB44e9943F39138"; 

// The ABI (Application Binary Interface) of your contract.
// This is a JSON representation of your contract's functions.
// You can get the full ABI from Remix in the "Compile" tab, under the contract,
// there is a button to "Copy ABI to clipboard".
const CONTRACT_ABI = [
    // --- Events ---
    "event ItemCreated(uint256 indexed id, string name, address indexed producer)",
    "event RoleGranted(address indexed account, string role)",

    // --- Role Management Functions ---
    "function addProducer(address _account)",
    "function addDistributor(address _account)",
    "function addRetailer(address _account)",
    "function isProducer(address) view returns (bool)",
    "function isDistributor(address) view returns (bool)",
    "function isRetailer(address) view returns (bool)",

    // --- Core Functions ---
    "function createItem(string memory _name, string memory _initialLocation)",
    "function shipItem(uint256 _id, address _recipient, string memory _location)",
    "function receiveItem(uint256 _id, string memory _location)",
    "function processItem(uint256 _id, string memory _location)",
    "function markForSale(uint256 _id, string memory _location)",
    "function markSold(uint256 _id, address _consumer, string memory _location)",

    // --- View Functions ---
    "function getItemSummary(uint256 _id) view returns (uint256 id, string memory name, address currentOwner, uint8 currentState)",
    "function getItemHistory(uint256 _id) view returns (tuple(uint256 timestamp, address actor, uint8 newState, string location)[] memory)"
];

// --- 2. SCRIPT LOGIC (Adapted for Remix) ---

/**
 * Main function to run our script.
 */
async function main() {
    try {
        // --- Setup Provider, Signer, and Contract ---
        // We initialize these *inside* main() to ensure the Remix env is ready.
        
        // ** FIX 1: Keep the "any" network fix **
        // We use Remix's injected 'web3' object to create a new Web3Provider.
        // We pass "any" as the second argument to tell ethers.js
        // to not be strict about the "unknown" Remix VM network.
        const provider = new ethers.providers.Web3Provider(web3.currentProvider, "any");
        
        const signer = provider.getSigner();
        const supplyChainContract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);

        const signerAddress = await signer.getAddress();
        console.log(`Connected to contract at ${CONTRACT_ADDRESS}`);
        console.log(`Using signer account: ${signerAddress}`);

        console.log("--- Starting Supply Chain Script ---");

        // We will use this address to grant a role to.
        // For this test, we'll just grant the role to ourselves.
        const producerAccount = signerAddress; 

        // --- 1. Read Data (View Function) ---
        console.log(`\nChecking if ${producerAccount} is a producer...`);
        
        // ** FIX 2: Add back the .functions workaround **
        // This bypasses the ENS check on view calls.
        // It returns an array, so we take the first element [0].
        let isProdArr = await supplyChainContract.functions.isProducer(producerAccount);
        let isProd = isProdArr[0];
        console.log(`Result: ${isProd}`);

        // --- 2. Write Data (Send Transaction) ---
        // Write transactions can be called normally.
        if (!isProd) {
            console.log("\nAccount is not a producer. Adding role...");
            const tx = await supplyChainContract.addProducer(producerAccount);
            await tx.wait();
            console.log("Transaction mined! Role added.");
            
            // Check again using the .functions syntax
            isProdArr = await supplyChainContract.functions.isProducer(producerAccount);
            isProd = isProdArr[0];
            console.log(`New check: ${producerAccount} is a producer? Result: ${isProd}`);
        }

        // --- 3. Write Data: Create an Item ---
        console.log("\nCreating a new item: 'Organic Coffee Batch #77'...");
        const createTx = await supplyChainContract.createItem(
            "Organic Coffee Batch #77",
            "Farm Warehouse A"
        );
        const receipt = await createTx.wait();
        
        // ** FIX for 'undefined is not valid JSON' error **
        // Changed this log to avoid a Remix console parsing bug.
        console.log("Item created! Transaction was mined.");
        
        // --- 4. Read Data: Get Item Summary ---
        console.log("\nFetching summary for Item ID 1...");
        
        // ** FIX 2: Use .functions workaround **
        // .functions.getItemSummary() returns an object that looks like an array
        const summary = await supplyChainContract.functions.getItemSummary(1);
        
        console.log("Item Summary for ID 1:");
        console.log(`  Name: ${summary.name}`);
        console.log(`  Owner: ${summary.currentOwner}`);
        console.log(`  State: ${summary.currentState.toString()} (0 = Created)`);

        // --- 5. Read Data: Get Item History ---
        console.log("\nFetching history for Item ID 1...");
        
        // ** FIX 2: Use .functions workaround **
        // This call is nested in an array, so we take [0]
        const historyArr = await supplyChainContract.functions.getItemHistory(1);
        const history = historyArr[0];
        
        console.log("Item History for ID 1:");
        history.forEach((event, index) => {
            console.log(`  Event ${index}:`);
            console.log(`    Timestamp: ${new Date(Number(event.timestamp) * 1000).toLocaleString()}`);
            console.log(`    Actor: ${event.actor}`);
            console.log(`    New State: ${event.newState.toString()}`);
            console.log(`    Location: ${event.location}`);
        });

        console.log("\n--- Script Finished Successfully ---");

    } catch (error) {
        console.error("\n--- An error occurred ---");
        console.error(error);
    }
}

// Run the main function
// We wrap it in a self-executing function to use await at the top level
(async () => {
    await main();
})();