// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/SealRegistry.sol";
import "../src/mocks/MockIdentityRegistry.sol";

/**
 * @title Interact
 * @dev Post-deployment interaction script for demos and testing
 *
 * Usage:
 *   # Set deployed addresses
 *   export IDENTITY_REGISTRY=0x...
 *   export SEAL_REGISTRY=0x...
 *   export PRIVATE_KEY=0x...
 *
 *   # Run specific demo function
 *   forge script script/Interact.s.sol \
 *     --rpc-url base_sepolia \
 *     --broadcast \
 *     --sig "demoAgentIssuesSeal()" \
 *     -vvvv
 *
 *   # Run full demo
 *   forge script script/Interact.s.sol \
 *     --rpc-url base_sepolia \
 *     --broadcast \
 *     -vvvv
 */
contract Interact is Script {
    SealRegistry public sealRegistry;
    MockIdentityRegistry public identityRegistry;

    // Demo addresses — override via environment or change here
    address constant DEMO_HUMAN = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        sealRegistry = SealRegistry(vm.envAddress("SEAL_REGISTRY"));
        identityRegistry = MockIdentityRegistry(vm.envAddress("IDENTITY_REGISTRY"));
    }

    /**
     * @dev Full demo: register agent, issue seals, query them
     */
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("=== describe-net Interaction Demo ===");
        console.log("Deployer / Actor:", deployer);
        console.log("SealRegistry:    ", address(sealRegistry));
        console.log("IdentityRegistry:", address(identityRegistry));
        console.log("");

        vm.startBroadcast(pk);

        // --- Step 1: Register deployer as an agent ---
        uint256 agentId = 100;
        identityRegistry.addAgent(agentId, "demo-agent.describe.net", deployer);
        console.log("[1] Registered deployer as agent ID:", agentId);

        // --- Step 2: Register seal domains for the agent ---
        bytes32[] memory domains = new bytes32[](3);
        domains[0] = keccak256("SKILLFUL");
        domains[1] = keccak256("RELIABLE");
        domains[2] = keccak256("THOROUGH");
        sealRegistry.registerAgentSealDomains(domains);
        console.log("[2] Registered 3 seal domains: SKILLFUL, RELIABLE, THOROUGH");

        // --- Step 3: Agent issues SKILLFUL seal to a human ---
        uint256 sealId1 = sealRegistry.issueSealA2H(
            DEMO_HUMAN,
            keccak256("SKILLFUL"),
            85,
            keccak256("demo-evidence-skillful"),
            0 // never expires
        );
        console.log("[3] Issued SKILLFUL seal (score 85) -> seal ID:", sealId1);

        // --- Step 4: Agent issues RELIABLE seal to same human ---
        uint256 sealId2 = sealRegistry.issueSealA2H(
            DEMO_HUMAN,
            keccak256("RELIABLE"),
            92,
            keccak256("demo-evidence-reliable"),
            uint48(block.timestamp + 365 days)
        );
        console.log("[4] Issued RELIABLE seal (score 92, 1yr expiry) -> seal ID:", sealId2);

        // --- Step 5: Human-to-Human seal (deployer to demo human) ---
        uint256 sealId3 =
            sealRegistry.issueSealH2H(DEMO_HUMAN, keccak256("CREATIVE"), 78, keccak256("demo-evidence-creative"));
        console.log("[5] Issued H2H CREATIVE seal (score 78) -> seal ID:", sealId3);

        vm.stopBroadcast();

        // --- Step 6: Query seals (read-only, no broadcast needed) ---
        console.log("");
        console.log("=== Querying Seals ===");

        uint256[] memory subjectSeals = sealRegistry.getSubjectSeals(DEMO_HUMAN);
        console.log("Total seals for demo human:", subjectSeals.length);

        for (uint256 i = 0; i < subjectSeals.length; i++) {
            SealRegistry.Seal memory seal = sealRegistry.getSeal(subjectSeals[i]);
            console.log("  Seal ID:", subjectSeals[i]);
            console.log("    Score:", seal.score);
            console.log("    Evaluator:", seal.evaluator);
            console.log("    Revoked:", seal.revoked);
        }

        uint256[] memory skillfulSeals = sealRegistry.getSubjectSealsByType(DEMO_HUMAN, keccak256("SKILLFUL"));
        console.log("");
        console.log("SKILLFUL seals for demo human:", skillfulSeals.length);

        console.log("");
        console.log("Total seals in registry:", sealRegistry.totalSeals());

        console.log("");
        console.log("=== Demo Complete ===");
    }

    /**
     * @dev Standalone: Agent issues a single SKILLFUL seal
     *      Requires the deployer to already be registered as an agent
     *      with SKILLFUL in their seal domains.
     */
    function demoAgentIssuesSeal() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address target = vm.envOr("TARGET_ADDRESS", DEMO_HUMAN);
        uint8 score = uint8(vm.envOr("SEAL_SCORE", uint256(85)));

        console.log("Issuing SKILLFUL seal to:", target, "score:", score);

        vm.startBroadcast(pk);

        uint256 sealId = sealRegistry.issueSealA2H(target, keccak256("SKILLFUL"), score, keccak256("cli-issued"), 0);

        vm.stopBroadcast();

        console.log("Seal issued! ID:", sealId);
    }

    /**
     * @dev Standalone: Query all seals for an address
     */
    function querySeals() external view {
        address target = vm.envOr("TARGET_ADDRESS", DEMO_HUMAN);

        console.log("=== Seals for", target, "===");

        uint256[] memory seals = sealRegistry.getSubjectSeals(target);
        console.log("Total seals:", seals.length);

        for (uint256 i = 0; i < seals.length; i++) {
            SealRegistry.Seal memory seal = sealRegistry.getSeal(seals[i]);
            console.log("");
            console.log("Seal ID:", seals[i]);
            console.log("  Score:    ", seal.score);
            console.log("  Evaluator:", seal.evaluator);
            console.log("  Quadrant: ", uint8(seal.quadrant));
            console.log("  Revoked:  ", seal.revoked);

            if (seal.expiresAt > 0) {
                bool expired = sealRegistry.isSealExpired(seals[i]);
                console.log("  Expired:  ", expired);
            }
        }
    }
}
