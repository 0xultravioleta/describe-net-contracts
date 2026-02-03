// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/SealRegistry.sol";
import "../src/mocks/MockIdentityRegistry.sol";

/**
 * @title Deploy
 * @dev Basic deployment script for Base Sepolia
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy MockIdentityRegistry first (in production this would be the real IdentityRegistry)
        MockIdentityRegistry identityRegistry = new MockIdentityRegistry();
        console.log("MockIdentityRegistry deployed to:", address(identityRegistry));
        
        // Deploy SealRegistry
        SealRegistry sealRegistry = new SealRegistry(address(identityRegistry));
        console.log("SealRegistry deployed to:", address(sealRegistry));
        
        // Optional: Register some test agents for demonstration
        _setupTestData(identityRegistry, sealRegistry);
        
        vm.stopBroadcast();
        
        console.log("Deployment completed successfully!");
        console.log("IdentityRegistry:", address(identityRegistry));
        console.log("SealRegistry:", address(sealRegistry));
    }
    
    /**
     * @dev Setup test data for demonstration (optional)
     */
    function _setupTestData(MockIdentityRegistry identityRegistry, SealRegistry sealRegistry) private {
        // Register sample agents
        identityRegistry.addAgent(1, "agent1.describe-net", 0x1234567890123456789012345678901234567890);
        identityRegistry.addAgent(2, "agent2.describe-net", 0x2345678901234567890123456789012345678901);
        
        console.log("Sample agents registered:");
        console.log("Agent 1: ID=1, Domain=agent1.describe-net, Address=0x1234567890123456789012345678901234567890");
        console.log("Agent 2: ID=2, Domain=agent2.describe-net, Address=0x2345678901234567890123456789012345678901");
    }
}