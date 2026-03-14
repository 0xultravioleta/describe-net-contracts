// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ERC8004ReputationAdapter.sol";
import "../src/SealRegistry.sol";
import "../src/mocks/MockIdentityRegistry.sol";
import "../src/interfaces/IERC8004ReputationAdapter.sol";

contract ERC8004ReputationAdapterTest is Test {
    ERC8004ReputationAdapter public adapter;
    SealRegistry public sealRegistry;
    MockIdentityRegistry public identityRegistry;

    address public owner = makeAddr("owner");
    address public human1 = makeAddr("human1");
    address public human2 = makeAddr("human2");
    address public agent1 = makeAddr("agent1");
    address public agent2 = makeAddr("agent2");

    uint256 constant AGENT1_ID = 1;
    uint256 constant AGENT2_ID = 2;

    bytes32 constant EVIDENCE_HASH = keccak256("evidence");

    // All 13 seal types
    string[] public allSealTypes = [
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

    string[] public allQuadrants = ["H2H", "H2A", "A2H", "A2A"];

    function setUp() public {
        vm.startPrank(owner);

        // Deploy contracts
        identityRegistry = new MockIdentityRegistry();
        sealRegistry = new SealRegistry(address(identityRegistry));
        adapter = new ERC8004ReputationAdapter(address(sealRegistry));

        // Register agents in identity registry
        identityRegistry.addAgent(AGENT1_ID, "agent1.com", agent1);
        identityRegistry.addAgent(AGENT2_ID, "agent2.com", agent2);

        vm.stopPrank();

        // Register agent seal domains for A2H testing
        vm.startPrank(agent1);
        bytes32[] memory sealTypes = new bytes32[](3);
        sealTypes[0] = sealRegistry.SKILLFUL();
        sealTypes[1] = sealRegistry.RELIABLE();
        sealTypes[2] = sealRegistry.THOROUGH();
        sealRegistry.registerAgentSealDomains(sealTypes);
        vm.stopPrank();
    }

    /// @dev Test basic giveFeedback functionality

    function test_giveFeedback_H2A_Success() public {
        vm.startPrank(human1);

        uint256 sealId = adapter.giveFeedback(
            AGENT1_ID, 85, 0, "SKILLFUL", "H2A", "https://endpoint.com", "https://feedback.uri", EVIDENCE_HASH
        );

        // Verify seal was created
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        assertEq(seal.subject, agent1);
        assertEq(seal.evaluator, address(adapter)); // Adapter is recorded as evaluator
        assertEq(seal.sealType, sealRegistry.SKILLFUL());
        assertEq(uint8(seal.quadrant), uint8(SealRegistry.Quadrant.H2A));
        assertEq(seal.score, 85);
        assertEq(seal.evidenceHash, EVIDENCE_HASH);

        vm.stopPrank();
    }

    function test_giveFeedback_H2H_Success() public {
        vm.startPrank(human1);

        // For H2H, we evaluate human2. Since human2 might not be an agent,
        // we can register human2 as a "fake agent" for testing purposes
        identityRegistry.addAgent(999, "human2.test", human2);

        uint256 sealId = adapter.giveFeedback(
            999, // human2's agent ID
            75,
            0,
            "PROFESSIONAL",
            "H2H",
            "",
            "",
            EVIDENCE_HASH
        );

        // Verify seal was created
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        assertEq(seal.subject, human2);
        assertEq(seal.evaluator, address(adapter)); // Adapter is recorded as evaluator
        assertEq(seal.sealType, sealRegistry.PROFESSIONAL());
        assertEq(uint8(seal.quadrant), uint8(SealRegistry.Quadrant.H2H));
        assertEq(seal.score, 75);

        vm.stopPrank();
    }

    function test_giveFeedback_A2H_NotSupported() public {
        vm.startPrank(agent1);

        // A2H is not supported via adapter since the adapter contract itself
        // is not registered as an agent and cannot proxy agent authorization
        vm.expectRevert("A2H not supported via adapter - agent must call SealRegistry directly");
        adapter.giveFeedback(AGENT2_ID, 90, 2, "SKILLFUL", "A2H", "", "ipfs://metadata", EVIDENCE_HASH);

        vm.stopPrank();
    }

    /// @dev Test score conversion (int128 → uint8 clamped 0-100)

    function test_giveFeedback_ScoreConversion_Clamp() public {
        vm.startPrank(human1);

        // Test negative value clamped to 0
        uint256 sealId1 = adapter.giveFeedback(AGENT1_ID, -50, 0, "SKILLFUL", "H2A", "", "", EVIDENCE_HASH);
        assertEq(sealRegistry.getSeal(sealId1).score, 0);

        // Test value > 100 clamped to 100
        uint256 sealId2 = adapter.giveFeedback(AGENT1_ID, 150, 0, "RELIABLE", "H2A", "", "", EVIDENCE_HASH);
        assertEq(sealRegistry.getSeal(sealId2).score, 100);

        // Test normal value preserved
        uint256 sealId3 = adapter.giveFeedback(AGENT1_ID, 85, 0, "THOROUGH", "H2A", "", "", EVIDENCE_HASH);
        assertEq(sealRegistry.getSeal(sealId3).score, 85);

        vm.stopPrank();
    }

    /// @dev Test all 12 seal type mappings

    function test_tag1ToSealType_AllMappings() public {
        // Test all 13 seal types are correctly mapped
        for (uint256 i = 0; i < 13; i++) {
            string memory sealTypeName = allSealTypes[i];
            bytes32 expectedHash = keccak256(bytes(sealTypeName));

            // Get the mapped hash from adapter
            bytes32 mappedHash = adapter.tag1ToSealType(sealTypeName);
            assertEq(mappedHash, expectedHash, string.concat("Failed for ", sealTypeName));

            // Test reverse mapping
            string memory reverseMapped = adapter.sealTypeToTag1(expectedHash);
            assertEq(keccak256(bytes(reverseMapped)), keccak256(bytes(sealTypeName)));
        }
    }

    function test_isValidTag1_AllSealTypes() public {
        // Test all valid seal types
        for (uint256 i = 0; i < 13; i++) {
            assertTrue(adapter.isValidTag1(allSealTypes[i]), string.concat("Should be valid: ", allSealTypes[i]));
        }

        // Test invalid seal type
        assertFalse(adapter.isValidTag1("INVALID_SEAL"));
        assertFalse(adapter.isValidTag1(""));
    }

    /// @dev Test quadrant mappings

    function test_tag2ToQuadrant_AllMappings() public {
        assertEq(uint8(adapter.tag2ToQuadrant("H2H")), uint8(SealRegistry.Quadrant.H2H));
        assertEq(uint8(adapter.tag2ToQuadrant("H2A")), uint8(SealRegistry.Quadrant.H2A));
        assertEq(uint8(adapter.tag2ToQuadrant("A2H")), uint8(SealRegistry.Quadrant.A2H));
        assertEq(uint8(adapter.tag2ToQuadrant("A2A")), uint8(SealRegistry.Quadrant.A2A));

        // Test reverse mappings
        assertEq(adapter.quadrantToTag2(SealRegistry.Quadrant.H2H), "H2H");
        assertEq(adapter.quadrantToTag2(SealRegistry.Quadrant.H2A), "H2A");
        assertEq(adapter.quadrantToTag2(SealRegistry.Quadrant.A2H), "A2H");
        assertEq(adapter.quadrantToTag2(SealRegistry.Quadrant.A2A), "A2A");
    }

    function test_isValidTag2_AllQuadrants() public {
        // Test all valid quadrants
        for (uint256 i = 0; i < 4; i++) {
            assertTrue(adapter.isValidTag2(allQuadrants[i]), string.concat("Should be valid: ", allQuadrants[i]));
        }

        // Test invalid quadrants
        assertFalse(adapter.isValidTag2("INVALID"));
        assertFalse(adapter.isValidTag2(""));
        assertFalse(adapter.isValidTag2("H2X"));
    }

    /// @dev Test ERC-8004 events

    function test_giveFeedback_EmitsEvent() public {
        vm.startPrank(human1);

        // Test event emission
        vm.expectEmit(true, true, true, true);
        emit IERC8004ReputationAdapter.FeedbackGiven(
            AGENT1_ID,
            human1,
            85,
            "SKILLFUL",
            "H2A",
            1 // sealId will be 1
        );

        adapter.giveFeedback(AGENT1_ID, 85, 0, "SKILLFUL", "H2A", "", "", EVIDENCE_HASH);

        vm.stopPrank();
    }

    /// @dev Test error cases

    function test_giveFeedback_RevertOn_InvalidTag1() public {
        vm.startPrank(human1);

        vm.expectRevert(abi.encodeWithSelector(IERC8004ReputationAdapter.InvalidTag1.selector, "INVALID_SEAL"));
        adapter.giveFeedback(AGENT1_ID, 85, 0, "INVALID_SEAL", "H2A", "", "", EVIDENCE_HASH);

        vm.stopPrank();
    }

    function test_giveFeedback_RevertOn_InvalidTag2() public {
        vm.startPrank(human1);

        vm.expectRevert(abi.encodeWithSelector(IERC8004ReputationAdapter.InvalidTag2.selector, "INVALID_QUAD"));
        adapter.giveFeedback(AGENT1_ID, 85, 0, "SKILLFUL", "INVALID_QUAD", "", "", EVIDENCE_HASH);

        vm.stopPrank();
    }

    function test_giveFeedback_RevertOn_SelfFeedback() public {
        vm.startPrank(agent1);

        vm.expectRevert(abi.encodeWithSelector(IERC8004ReputationAdapter.SelfFeedbackNotAllowed.selector, agent1));
        adapter.giveFeedback(AGENT1_ID, 85, 0, "SKILLFUL", "H2A", "", "", EVIDENCE_HASH);

        vm.stopPrank();
    }

    function test_giveFeedback_RevertOn_NonexistentAgent() public {
        vm.startPrank(human1);

        // This should revert when the underlying SealRegistry tries to process
        // a nonexistent agent ID
        vm.expectRevert();
        adapter.giveFeedback(
            999, // Nonexistent agent ID
            85,
            0,
            "SKILLFUL",
            "H2A",
            "",
            "",
            EVIDENCE_HASH
        );

        vm.stopPrank();
    }

    /// @dev Test round-trip: giveFeedback → getFeedbackAsERC8004

    function test_roundTrip_PreservesData() public {
        vm.startPrank(human1);

        uint256 sealId = adapter.giveFeedback(
            AGENT1_ID, 85, 2, "SKILLFUL", "H2A", "https://endpoint.test", "https://feedback.uri", EVIDENCE_HASH
        );

        // Get feedback in ERC-8004 format
        IERC8004ReputationAdapter.ERC8004Feedback memory feedback = adapter.getFeedbackAsERC8004(sealId);

        // Verify all data is preserved
        assertEq(feedback.agentId, AGENT1_ID);
        assertEq(feedback.submitter, human1);
        assertEq(feedback.value, 85);
        assertEq(feedback.valueDecimals, 2);
        assertEq(feedback.tag1, "SKILLFUL");
        assertEq(feedback.tag2, "H2A");
        assertEq(feedback.endpoint, "https://endpoint.test");
        assertEq(feedback.feedbackURI, "https://feedback.uri");
        assertEq(feedback.feedbackHash, EVIDENCE_HASH);
        assertGt(feedback.timestamp, 0); // Should have a timestamp

        vm.stopPrank();
    }

    /// @dev Test feedbackToSeal conversion function

    function test_feedbackToSeal_Conversion() public {
        (address subject, bytes32 sealType, uint8 quadrant, uint8 score, bytes32 evidenceHash) =
            adapter.feedbackToSeal(AGENT1_ID, 85, "SKILLFUL", "H2A", EVIDENCE_HASH);

        assertEq(subject, agent1);
        assertEq(sealType, sealRegistry.SKILLFUL());
        assertEq(quadrant, uint8(SealRegistry.Quadrant.H2A));
        assertEq(score, 85);
        assertEq(evidenceHash, EVIDENCE_HASH);
    }

    /// @dev Test adapter works with existing SealRegistry

    function test_adapter_WorksWithExistingSealRegistry() public {
        // Issue a seal directly through SealRegistry
        vm.startPrank(human1);
        uint256 directSealId = sealRegistry.issueSealH2A(AGENT1_ID, sealRegistry.RELIABLE(), 90, keccak256("direct"));
        vm.stopPrank();

        // Issue a seal through adapter
        vm.startPrank(human2);
        uint256 adapterSealId = adapter.giveFeedback(AGENT1_ID, 80, 0, "SKILLFUL", "H2A", "", "", keccak256("adapter"));
        vm.stopPrank();

        // Both seals should exist and be different
        assertTrue(directSealId != adapterSealId);

        SealRegistry.Seal memory directSeal = sealRegistry.getSeal(directSealId);
        SealRegistry.Seal memory adapterSeal = sealRegistry.getSeal(adapterSealId);

        assertEq(directSeal.subject, agent1);
        assertEq(adapterSeal.subject, agent1);
        assertEq(directSeal.score, 90);
        assertEq(adapterSeal.score, 80);
    }

    /// @dev Test sealToFeedback works with direct seals

    function test_sealToFeedback_WorksWithDirectSeals() public {
        // Issue a seal directly through SealRegistry
        vm.startPrank(human1);
        uint256 sealId = sealRegistry.issueSealH2A(AGENT1_ID, sealRegistry.RELIABLE(), 90, keccak256("direct"));
        vm.stopPrank();

        // Convert to ERC-8004 format - this should work even though
        // the seal was created directly, though metadata will be empty
        IERC8004ReputationAdapter.ERC8004Feedback memory feedback = adapter.sealToFeedback(sealId);

        assertEq(feedback.agentId, AGENT1_ID);
        assertEq(feedback.submitter, human1);
        assertEq(feedback.value, 90);
        assertEq(feedback.tag1, "RELIABLE");
        assertEq(feedback.tag2, "H2A");
        assertEq(feedback.feedbackHash, keccak256("direct"));
        // Metadata fields should be empty for direct seals
        assertEq(feedback.valueDecimals, 0);
        assertEq(feedback.endpoint, "");
        assertEq(feedback.feedbackURI, "");
    }

    /// @dev Test edge cases

    function test_giveFeedback_EdgeCases() public {
        vm.startPrank(human1);

        // Test with zero value
        uint256 sealId1 = adapter.giveFeedback(AGENT1_ID, 0, 0, "SKILLFUL", "H2A", "", "", bytes32(0));
        assertEq(sealRegistry.getSeal(sealId1).score, 0);

        // Test with max value
        uint256 sealId2 = adapter.giveFeedback(AGENT1_ID, 100, 0, "RELIABLE", "H2A", "", "", bytes32(0));
        assertEq(sealRegistry.getSeal(sealId2).score, 100);

        // Test with empty strings
        uint256 sealId3 = adapter.giveFeedback(AGENT1_ID, 50, 0, "THOROUGH", "H2A", "", "", bytes32(0));
        IERC8004ReputationAdapter.ERC8004Feedback memory feedback = adapter.getFeedbackAsERC8004(sealId3);
        assertEq(feedback.endpoint, "");
        assertEq(feedback.feedbackURI, "");

        vm.stopPrank();
    }

    /// @dev Test comprehensive tag mappings

    function test_comprehensive_TagMappings() public {
        vm.startPrank(human1);

        // Test each seal type with H2A quadrant
        for (uint256 i = 0; i < 13; i++) {
            string memory sealTypeName = allSealTypes[i];

            uint256 sealId =
                adapter.giveFeedback(AGENT1_ID, int128(uint128(50 + i)), 0, sealTypeName, "H2A", "", "", EVIDENCE_HASH);

            SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
            bytes32 expectedSealType = keccak256(bytes(sealTypeName));

            assertEq(seal.sealType, expectedSealType, string.concat("Seal type mismatch for ", sealTypeName));
            assertEq(seal.score, 50 + i);

            // Test round-trip
            IERC8004ReputationAdapter.ERC8004Feedback memory feedback = adapter.getFeedbackAsERC8004(sealId);
            assertEq(feedback.tag1, sealTypeName);
            assertEq(feedback.tag2, "H2A");
        }

        vm.stopPrank();
    }
}
