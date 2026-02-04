// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/SealRegistry.sol";
import "../src/mocks/MockIdentityRegistry.sol";

/**
 * @title Deploy
 * @dev Full deployment script for SealRegistry on Base Sepolia
 *
 * Usage:
 *   forge script script/Deploy.s.sol \
 *     --rpc-url base_sepolia \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 *
 * Environment:
 *   PRIVATE_KEY       - Deployer private key
 *   BASESCAN_API_KEY  - Basescan API key for verification (optional)
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== describe-net SealRegistry Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy MockIdentityRegistry (testnet only — production uses real IdentityRegistry)
        MockIdentityRegistry identityRegistry = new MockIdentityRegistry();
        console.log("[1/2] MockIdentityRegistry deployed:", address(identityRegistry));

        // 2. Deploy SealRegistry pointing to mock registry
        SealRegistry sealRegistry = new SealRegistry(address(identityRegistry));
        console.log("[2/2] SealRegistry deployed:         ", address(sealRegistry));

        // 3. Verify seal types were initialized
        console.log("");
        console.log("=== Verifying Seal Types ===");
        _verifySealTypes(sealRegistry);

        vm.stopBroadcast();

        // 4. Summary
        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("Network:              Base Sepolia (84532)");
        console.log("MockIdentityRegistry:", address(identityRegistry));
        console.log("SealRegistry:         ", address(sealRegistry));
        console.log("Owner:                ", deployer);
        console.log("");
        console.log("Next steps:");
        console.log("  1. Update deployments/base-sepolia.json with addresses");
        console.log("  2. Verify on Basescan if --verify flag was not used:");
        console.log("     forge verify-contract <ADDRESS> SealRegistry --chain base-sepolia");
        console.log("  3. Register test agents via MockIdentityRegistry.addAgent()");
        console.log("  4. Run script/Interact.s.sol for demo interactions");
    }

    function _verifySealTypes(SealRegistry sealRegistry) private view {
        string[13] memory sealNames = [
            "SKILLFUL",
            "RELIABLE",
            "THOROUGH",
            "ENGAGED",
            "HELPFUL",
            "CURIOUS",
            "FAIR",
            "ACCURATE",
            "RESPONSIVE",
            "ETHICAL",
            "CREATIVE",
            "PROFESSIONAL",
            "FRIENDLY"
        ];

        for (uint256 i = 0; i < sealNames.length; i++) {
            bytes32 sealType = keccak256(abi.encodePacked(sealNames[i]));
            bool valid = sealRegistry.isValidSealType(sealType);
            console.log(
                string.concat("  ", sealNames[i], ": ", valid ? "OK" : "MISSING")
            );
        }
    }
}
