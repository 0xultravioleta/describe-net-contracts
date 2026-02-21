// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SealRegistry.sol";
import "../src/mocks/MockIdentityRegistry.sol";

contract SealRegistryTest is Test {
    SealRegistry public sealRegistry;
    MockIdentityRegistry public identityRegistry;
    
    address public owner = makeAddr("owner");
    address public human1 = makeAddr("human1");
    address public human2 = makeAddr("human2");
    address public agent1 = makeAddr("agent1");
    address public agent2 = makeAddr("agent2");
    
    uint256 constant AGENT1_ID = 1;
    uint256 constant AGENT2_ID = 2;
    
    bytes32 constant SKILLFUL = keccak256("SKILLFUL");
    bytes32 constant RELIABLE = keccak256("RELIABLE");
    bytes32 constant FAIR = keccak256("FAIR");
    bytes32 constant CREATIVE = keccak256("CREATIVE");
    bytes32 constant INVALID_SEAL = keccak256("INVALID");
    
    bytes32 constant EVIDENCE_HASH = keccak256("evidence");
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy contracts
        identityRegistry = new MockIdentityRegistry();
        sealRegistry = new SealRegistry(address(identityRegistry));
        
        // Register agents in identity registry
        identityRegistry.addAgent(AGENT1_ID, "agent1.com", agent1);
        identityRegistry.addAgent(AGENT2_ID, "agent2.com", agent2);
        
        vm.stopPrank();
        
        // Register agent seal domains
        vm.startPrank(agent1);
        bytes32[] memory sealTypes = new bytes32[](3);
        sealTypes[0] = SKILLFUL;
        sealTypes[1] = RELIABLE;
        sealTypes[2] = keccak256("THOROUGH");
        sealRegistry.registerAgentSealDomains(sealTypes);
        vm.stopPrank();
    }

    /// @dev Test A→H seal issuance (happy path)
    function testIssueSealA2H_HappyPath() public {
        vm.prank(agent1);
        
        uint256 sealId = sealRegistry.issueSealA2H(
            human1,
            SKILLFUL,
            85,
            EVIDENCE_HASH,
            uint48(block.timestamp + 1 days)
        );
        
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        
        assertEq(uint(seal.sealType), uint(SKILLFUL));
        assertEq(seal.subject, human1);
        assertEq(seal.evaluator, agent1);
        assertEq(uint8(seal.quadrant), uint8(SealRegistry.Quadrant.A2H));
        assertEq(seal.score, 85);
        assertEq(seal.evidenceHash, EVIDENCE_HASH);
        assertEq(seal.issuedAt, uint48(block.timestamp));
        assertEq(seal.expiresAt, uint48(block.timestamp + 1 days));
        assertFalse(seal.revoked);
        
        // Check seal is in subject's list
        uint256[] memory subjectSeals = sealRegistry.getSubjectSeals(human1);
        assertEq(subjectSeals.length, 1);
        assertEq(subjectSeals[0], sealId);
        
        // Check seal is in evaluator's list
        uint256[] memory evaluatorSeals = sealRegistry.getEvaluatorSeals(agent1);
        assertEq(evaluatorSeals.length, 1);
        assertEq(evaluatorSeals[0], sealId);
    }

    /// @dev Test H→A seal issuance (happy path)
    function testIssueSealH2A_HappyPath() public {
        vm.prank(human1);
        
        uint256 sealId = sealRegistry.issueSealH2A(
            AGENT1_ID,
            FAIR,
            90,
            EVIDENCE_HASH
        );
        
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        
        assertEq(uint(seal.sealType), uint(FAIR));
        assertEq(seal.subject, agent1);
        assertEq(seal.evaluator, human1);
        assertEq(uint8(seal.quadrant), uint8(SealRegistry.Quadrant.H2A));
        assertEq(seal.score, 90);
        assertEq(seal.expiresAt, 0); // Never expires
        assertFalse(seal.revoked);
    }

    /// @dev Test H→H seal issuance (happy path)
    function testIssueSealH2H_HappyPath() public {
        vm.prank(human1);
        
        uint256 sealId = sealRegistry.issueSealH2H(
            human2,
            CREATIVE,
            75,
            EVIDENCE_HASH
        );
        
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        
        assertEq(uint(seal.sealType), uint(CREATIVE));
        assertEq(seal.subject, human2);
        assertEq(seal.evaluator, human1);
        assertEq(uint8(seal.quadrant), uint8(SealRegistry.Quadrant.H2H));
        assertEq(seal.score, 75);
        assertFalse(seal.revoked);
    }

    /// @dev Test seal revocation (only by evaluator)
    function testRevokeSeal_OnlyByEvaluator() public {
        // Issue a seal first
        vm.prank(human1);
        uint256 sealId = sealRegistry.issueSealH2H(human2, CREATIVE, 75, EVIDENCE_HASH);
        
        // Try to revoke by non-evaluator - should fail
        vm.expectRevert(SealRegistry.UnauthorizedEvaluator.selector);
        vm.prank(human2);
        sealRegistry.revokeSeal(sealId, "Unauthorized attempt");
        
        // Revoke by evaluator - should succeed
        vm.prank(human1);
        sealRegistry.revokeSeal(sealId, "Changed my mind");
        
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        assertTrue(seal.revoked);
    }

    /// @dev Test unauthorized agent can't issue seals for unregistered types
    function testIssueSealA2H_UnauthorizedSealType() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SealRegistry.AgentNotAuthorizedForSealType.selector,
                agent1,
                FAIR
            )
        );
        
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, FAIR, 85, EVIDENCE_HASH, 0);
    }

    /// @dev Test unregistered address can't issue A→H seals
    function testIssueSealA2H_UnregisteredAgent() public {
        address unregisteredAgent = makeAddr("unregistered");
        
        vm.expectRevert(
            abi.encodeWithSelector(SealRegistry.AgentNotRegistered.selector, unregisteredAgent)
        );
        
        vm.prank(unregisteredAgent);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 85, EVIDENCE_HASH, 0);
    }

    /// @dev Test invalid seal type reverts
    function testInvalidSealType() public {
        vm.expectRevert(abi.encodeWithSelector(SealRegistry.InvalidSealType.selector, INVALID_SEAL));
        
        vm.prank(human1);
        sealRegistry.issueSealH2H(human2, INVALID_SEAL, 75, EVIDENCE_HASH);
    }

    /// @dev Test score > 100 reverts
    function testInvalidScore() public {
        vm.expectRevert(abi.encodeWithSelector(SealRegistry.InvalidScore.selector, 101));
        
        vm.prank(human1);
        sealRegistry.issueSealH2H(human2, CREATIVE, 101, EVIDENCE_HASH);
    }

    /// @dev Test expired seal detection
    function testExpiredSealDetection() public {
        uint48 expirationTime = uint48(block.timestamp + 1 hours);
        
        vm.prank(agent1);
        uint256 sealId = sealRegistry.issueSealA2H(
            human1,
            SKILLFUL,
            85,
            EVIDENCE_HASH,
            expirationTime
        );
        
        // Seal should not be expired yet
        assertFalse(sealRegistry.isSealExpired(sealId));
        
        // Warp time forward
        vm.warp(block.timestamp + 2 hours);
        
        // Seal should now be expired
        assertTrue(sealRegistry.isSealExpired(sealId));
    }

    /// @dev Test never-expiring seals
    function testNeverExpiringSeals() public {
        vm.prank(human1);
        uint256 sealId = sealRegistry.issueSealH2H(human2, CREATIVE, 75, EVIDENCE_HASH);
        
        // Seal should never expire (expiresAt = 0)
        assertFalse(sealRegistry.isSealExpired(sealId));
        
        // Even after a long time
        vm.warp(block.timestamp + 365 days);
        assertFalse(sealRegistry.isSealExpired(sealId));
    }

    /// @dev Test getSubjectSeals returns correct seals
    function testGetSubjectSeals() public {
        // Issue multiple seals to human1
        vm.prank(human2);
        uint256 seal1 = sealRegistry.issueSealH2H(human1, CREATIVE, 75, EVIDENCE_HASH);
        
        vm.prank(agent1);
        uint256 seal2 = sealRegistry.issueSealA2H(human1, SKILLFUL, 85, EVIDENCE_HASH, 0);
        
        uint256[] memory seals = sealRegistry.getSubjectSeals(human1);
        assertEq(seals.length, 2);
        assertEq(seals[0], seal1);
        assertEq(seals[1], seal2);
    }

    /// @dev Test getSubjectSealsByType filtering
    function testGetSubjectSealsByType() public {
        // Issue multiple seals of different types
        vm.prank(agent1);
        uint256 seal1 = sealRegistry.issueSealA2H(human1, SKILLFUL, 85, EVIDENCE_HASH, 0);
        
        vm.prank(agent1);
        uint256 seal2 = sealRegistry.issueSealA2H(human1, RELIABLE, 90, EVIDENCE_HASH, 0);
        
        vm.prank(agent1);
        uint256 seal3 = sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE_HASH, 0);
        
        // Get only SKILLFUL seals
        uint256[] memory skillfulSeals = sealRegistry.getSubjectSealsByType(human1, SKILLFUL);
        assertEq(skillfulSeals.length, 2);
        assertEq(skillfulSeals[0], seal1);
        assertEq(skillfulSeals[1], seal3);
        
        // Get only RELIABLE seals
        uint256[] memory reliableSeals = sealRegistry.getSubjectSealsByType(human1, RELIABLE);
        assertEq(reliableSeals.length, 1);
        assertEq(reliableSeals[0], seal2);
    }

    /// @dev Test addSealType by owner only
    function testAddSealType_OwnerOnly() public {
        bytes32 newSealType = keccak256("NEW_SEAL");
        
        // Should fail when called by non-owner
        vm.expectRevert();
        vm.prank(human1);
        sealRegistry.addSealType(newSealType);
        
        // Should succeed when called by owner
        vm.prank(owner);
        sealRegistry.addSealType(newSealType);
        
        assertTrue(sealRegistry.isValidSealType(newSealType));
    }

    /// @dev Test registerAgentSealDomains
    function testRegisterAgentSealDomains() public {
        // Agent should be able to register seal domains
        bytes32[] memory sealTypes = new bytes32[](2);
        sealTypes[0] = FAIR;
        sealTypes[1] = keccak256("ACCURATE");
        
        vm.prank(agent1);
        sealRegistry.registerAgentSealDomains(sealTypes);
        
        assertTrue(sealRegistry.getAgentSealDomains(agent1, FAIR));
        assertTrue(sealRegistry.getAgentSealDomains(agent1, keccak256("ACCURATE")));
    }

    /// @dev Test unregistered human can't register seal domains
    function testRegisterAgentSealDomains_UnregisteredHuman() public {
        bytes32[] memory sealTypes = new bytes32[](1);
        sealTypes[0] = FAIR;
        
        vm.expectRevert(abi.encodeWithSelector(SealRegistry.AgentNotRegistered.selector, human1));
        
        vm.prank(human1);
        sealRegistry.registerAgentSealDomains(sealTypes);
    }

    /// @dev Test revoke already revoked seal
    function testRevokeAlreadyRevokedSeal() public {
        // Issue and revoke a seal
        vm.prank(human1);
        uint256 sealId = sealRegistry.issueSealH2H(human2, CREATIVE, 75, EVIDENCE_HASH);
        
        vm.prank(human1);
        sealRegistry.revokeSeal(sealId, "First revocation");
        
        // Try to revoke again
        vm.expectRevert(abi.encodeWithSelector(SealRegistry.SealAlreadyRevoked.selector, sealId));
        
        vm.prank(human1);
        sealRegistry.revokeSeal(sealId, "Second revocation");
    }

    /// @dev Test getSeal with non-existent ID
    function testGetSeal_NonExistent() public {
        vm.expectRevert(abi.encodeWithSelector(SealRegistry.SealNotFound.selector, 999));
        sealRegistry.getSeal(999);
    }

    /// @dev Test H2A with non-existent agent
    function testIssueSealH2A_NonExistentAgent() public {
        vm.expectRevert(abi.encodeWithSelector(SealRegistry.AgentNotRegistered.selector, address(0)));
        
        vm.prank(human1);
        sealRegistry.issueSealH2A(999, FAIR, 85, EVIDENCE_HASH);
    }

    /// @dev Test totalSeals counter
    function testTotalSeals() public {
        assertEq(sealRegistry.totalSeals(), 0);
        
        vm.prank(human1);
        sealRegistry.issueSealH2H(human2, CREATIVE, 75, EVIDENCE_HASH);
        assertEq(sealRegistry.totalSeals(), 1);
        
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 85, EVIDENCE_HASH, 0);
        assertEq(sealRegistry.totalSeals(), 2);
    }

    /// @dev Test all view functions return expected values
    function testViewFunctions() public {
        // Test isValidSealType
        assertTrue(sealRegistry.isValidSealType(SKILLFUL));
        assertTrue(sealRegistry.isValidSealType(FAIR));
        assertTrue(sealRegistry.isValidSealType(CREATIVE));
        assertFalse(sealRegistry.isValidSealType(INVALID_SEAL));
        
        // Test getAgentSealDomains
        assertTrue(sealRegistry.getAgentSealDomains(agent1, SKILLFUL));
        assertFalse(sealRegistry.getAgentSealDomains(agent1, FAIR));
        assertFalse(sealRegistry.getAgentSealDomains(human1, SKILLFUL));
    }

    /// @dev Test events are emitted correctly
    function testEvents() public {
        // Test SealIssued event
        vm.expectEmit(true, true, true, true);
        emit SealRegistry.SealIssued(
            1,
            CREATIVE,
            human2,
            human1,
            SealRegistry.Quadrant.H2H,
            75
        );
        
        vm.prank(human1);
        sealRegistry.issueSealH2H(human2, CREATIVE, 75, EVIDENCE_HASH);
        
        // Test SealRevoked event
        vm.expectEmit(true, true, false, true);
        emit SealRegistry.SealRevoked(1, human1, "Test revocation");
        
        vm.prank(human1);
        sealRegistry.revokeSeal(1, "Test revocation");
        
        // Test SealTypeAdded event
        bytes32 newSealType = keccak256("NEW_SEAL");
        vm.expectEmit(true, false, false, true);
        emit SealRegistry.SealTypeAdded(newSealType);
        
        vm.prank(owner);
        sealRegistry.addSealType(newSealType);
        
        // Test AgentDomainsUpdated event
        bytes32[] memory sealTypes = new bytes32[](1);
        sealTypes[0] = FAIR;
        
        vm.expectEmit(true, false, false, true);
        emit SealRegistry.AgentDomainsUpdated(agent1, sealTypes);
        
        vm.prank(agent1);
        sealRegistry.registerAgentSealDomains(sealTypes);
    }

    // ============================================================
    // EDGE CASE TESTS - Expiration, Revocation, Domain, Quadrant
    // ============================================================

    /// @dev Test expiration at exact boundary timestamp
    function testExpirationBoundary_ExactTimestamp() public {
        uint48 expirationTime = uint48(block.timestamp + 1 hours);
        
        vm.prank(agent1);
        uint256 sealId = sealRegistry.issueSealA2H(
            human1,
            SKILLFUL,
            85,
            EVIDENCE_HASH,
            expirationTime
        );
        
        // At exactly expiration time, seal should NOT be expired (boundary is >)
        vm.warp(expirationTime);
        assertFalse(sealRegistry.isSealExpired(sealId));
        
        // One second after expiration, seal SHOULD be expired
        vm.warp(expirationTime + 1);
        assertTrue(sealRegistry.isSealExpired(sealId));
    }

    /// @dev Test seal with expiration set to block.timestamp (immediately expired)
    function testExpirationEdge_ImmediateExpiration() public {
        uint48 currentTime = uint48(block.timestamp);
        
        vm.prank(agent1);
        uint256 sealId = sealRegistry.issueSealA2H(
            human1,
            SKILLFUL,
            85,
            EVIDENCE_HASH,
            currentTime  // Expires at current time
        );
        
        // At issuance time, not yet expired (condition is >)
        assertFalse(sealRegistry.isSealExpired(sealId));
        
        // Any time after, it's expired
        vm.warp(currentTime + 1);
        assertTrue(sealRegistry.isSealExpired(sealId));
    }

    /// @dev Test isSealExpired on non-existent seal
    function testExpiration_NonExistentSeal() public {
        vm.expectRevert(abi.encodeWithSelector(SealRegistry.SealNotFound.selector, 999));
        sealRegistry.isSealExpired(999);
    }

    /// @dev Test revoke non-existent seal
    function testRevoke_NonExistentSeal() public {
        vm.expectRevert(abi.encodeWithSelector(SealRegistry.SealNotFound.selector, 999));
        vm.prank(human1);
        sealRegistry.revokeSeal(999, "Trying to revoke nothing");
    }

    /// @dev Test self-sealing (human sealing themselves H2H)
    function testSelfSealing_H2H() public {
        // Currently no restriction on self-sealing - verify it works
        vm.prank(human1);
        uint256 sealId = sealRegistry.issueSealH2H(
            human1,  // Subject is same as evaluator
            CREATIVE,
            100,
            EVIDENCE_HASH
        );
        
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        assertEq(seal.subject, human1);
        assertEq(seal.evaluator, human1);
        assertEq(uint8(seal.quadrant), uint8(SealRegistry.Quadrant.H2H));
    }

    /// @dev Test score boundary - minimum valid score (0)
    function testScoreBoundary_MinimumScore() public {
        vm.prank(human1);
        uint256 sealId = sealRegistry.issueSealH2H(human2, CREATIVE, 0, EVIDENCE_HASH);
        
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        assertEq(seal.score, 0);
    }

    /// @dev Test score boundary - maximum valid score (100)
    function testScoreBoundary_MaximumScore() public {
        vm.prank(human1);
        uint256 sealId = sealRegistry.issueSealH2H(human2, CREATIVE, 100, EVIDENCE_HASH);
        
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        assertEq(seal.score, 100);
    }

    /// @dev Test empty evidence hash is allowed
    function testEmptyEvidenceHash() public {
        vm.prank(human1);
        uint256 sealId = sealRegistry.issueSealH2H(human2, CREATIVE, 75, bytes32(0));
        
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        assertEq(seal.evidenceHash, bytes32(0));
    }

    /// @dev Test agent cannot issue same seal type multiple times in different domains
    function testAgentMultipleDomainRegistrations() public {
        // Register agent2 with different domains
        vm.startPrank(agent2);
        
        bytes32[] memory sealTypes1 = new bytes32[](1);
        sealTypes1[0] = SKILLFUL;
        sealRegistry.registerAgentSealDomains(sealTypes1);
        
        // Register additional domains - old ones should still be valid
        bytes32[] memory sealTypes2 = new bytes32[](1);
        sealTypes2[0] = RELIABLE;
        sealRegistry.registerAgentSealDomains(sealTypes2);
        
        vm.stopPrank();
        
        // Both should now be valid
        assertTrue(sealRegistry.getAgentSealDomains(agent2, SKILLFUL));
        assertTrue(sealRegistry.getAgentSealDomains(agent2, RELIABLE));
    }

    /// @dev Test registering invalid seal type in agent domains
    function testRegisterAgentSealDomains_InvalidSealType() public {
        bytes32[] memory sealTypes = new bytes32[](2);
        sealTypes[0] = SKILLFUL;
        sealTypes[1] = INVALID_SEAL;  // This is not a valid seal type
        
        vm.expectRevert(abi.encodeWithSelector(SealRegistry.InvalidSealType.selector, INVALID_SEAL));
        
        vm.prank(agent1);
        sealRegistry.registerAgentSealDomains(sealTypes);
    }

    /// @dev Test quadrant integrity - verify A2H seals have correct quadrant
    function testQuadrantIntegrity_A2H() public {
        vm.prank(agent1);
        uint256 sealId = sealRegistry.issueSealA2H(human1, SKILLFUL, 85, EVIDENCE_HASH, 0);
        
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        assertEq(uint8(seal.quadrant), uint8(SealRegistry.Quadrant.A2H));
        
        // Verify evaluator is agent
        IIdentityRegistry.AgentInfo memory info = identityRegistry.resolveByAddress(seal.evaluator);
        assertTrue(info.agentId != 0, "Evaluator should be a registered agent");
    }

    /// @dev Test quadrant integrity - verify H2A seals have correct quadrant
    function testQuadrantIntegrity_H2A() public {
        vm.prank(human1);
        uint256 sealId = sealRegistry.issueSealH2A(AGENT1_ID, FAIR, 90, EVIDENCE_HASH);
        
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        assertEq(uint8(seal.quadrant), uint8(SealRegistry.Quadrant.H2A));
        
        // Verify subject is an agent
        IIdentityRegistry.AgentInfo memory info = identityRegistry.resolveByAddress(seal.subject);
        assertTrue(info.agentId != 0, "Subject should be a registered agent");
    }

    /// @dev Test sealing to zero address (should be allowed but is edge case)
    function testSealToZeroAddress() public {
        vm.prank(human1);
        uint256 sealId = sealRegistry.issueSealH2H(
            address(0),  // Zero address as subject
            CREATIVE,
            75,
            EVIDENCE_HASH
        );
        
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        assertEq(seal.subject, address(0));
    }

    /// @dev Test large number of seals to same subject (gas/storage test)
    function testManySealsToSameSubject() public {
        uint256 numSeals = 50;
        
        for (uint256 i = 0; i < numSeals; i++) {
            vm.prank(human1);
            sealRegistry.issueSealH2H(human2, CREATIVE, uint8(i % 101), EVIDENCE_HASH);
        }
        
        uint256[] memory seals = sealRegistry.getSubjectSeals(human2);
        assertEq(seals.length, numSeals);
        assertEq(sealRegistry.totalSeals(), numSeals);
    }

    /// @dev Test revoked seal can still be queried (data persists)
    function testRevokedSealDataPersists() public {
        vm.prank(human1);
        uint256 sealId = sealRegistry.issueSealH2H(human2, CREATIVE, 85, EVIDENCE_HASH);
        
        vm.prank(human1);
        sealRegistry.revokeSeal(sealId, "Changed my mind");
        
        // Seal data should still be accessible
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        assertEq(seal.score, 85);
        assertEq(seal.subject, human2);
        assertTrue(seal.revoked);
        
        // Should still appear in subject's seal list
        uint256[] memory seals = sealRegistry.getSubjectSeals(human2);
        assertEq(seals.length, 1);
        assertEq(seals[0], sealId);
    }

    /// @dev Test expired seal data persists and is still queryable
    function testExpiredSealDataPersists() public {
        uint48 expirationTime = uint48(block.timestamp + 1 hours);
        
        vm.prank(agent1);
        uint256 sealId = sealRegistry.issueSealA2H(human1, SKILLFUL, 92, EVIDENCE_HASH, expirationTime);
        
        vm.warp(block.timestamp + 2 hours);
        
        // Seal should be expired
        assertTrue(sealRegistry.isSealExpired(sealId));
        
        // But data should persist
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        assertEq(seal.score, 92);
        assertEq(seal.sealType, SKILLFUL);
        assertEq(seal.expiresAt, expirationTime);
    }

    /// @dev Test fuzz - score validation
    function testFuzz_ScoreValidation(uint8 score) public {
        if (score > 100) {
            vm.expectRevert(abi.encodeWithSelector(SealRegistry.InvalidScore.selector, score));
        }
        
        vm.prank(human1);
        sealRegistry.issueSealH2H(human2, CREATIVE, score, EVIDENCE_HASH);
    }

    /// @dev Test that different agents can issue seals for same type independently
    function testMultipleAgentsSameSealType() public {
        // Register agent2 with SKILLFUL domain
        vm.prank(agent2);
        bytes32[] memory sealTypes = new bytes32[](1);
        sealTypes[0] = SKILLFUL;
        sealRegistry.registerAgentSealDomains(sealTypes);
        
        // Both agents issue SKILLFUL seals
        vm.prank(agent1);
        uint256 seal1 = sealRegistry.issueSealA2H(human1, SKILLFUL, 85, EVIDENCE_HASH, 0);
        
        vm.prank(agent2);
        uint256 seal2 = sealRegistry.issueSealA2H(human1, SKILLFUL, 90, EVIDENCE_HASH, 0);
        
        // Both seals should exist
        assertEq(sealRegistry.getSeal(seal1).evaluator, agent1);
        assertEq(sealRegistry.getSeal(seal2).evaluator, agent2);
        
        // Human1 should have 2 SKILLFUL seals
        uint256[] memory skillfulSeals = sealRegistry.getSubjectSealsByType(human1, SKILLFUL);
        assertEq(skillfulSeals.length, 2);
    }

    // ============================================================
    // A2A (Agent-to-Agent) Tests
    // ============================================================

    /// @dev Test A2A seal issuance (happy path)
    function testIssueSealA2A_HappyPath() public {
        // Register agent2 with SKILLFUL domain
        vm.prank(agent2);
        bytes32[] memory sealTypes = new bytes32[](2);
        sealTypes[0] = SKILLFUL;
        sealTypes[1] = RELIABLE;
        sealRegistry.registerAgentSealDomains(sealTypes);

        // Agent2 evaluates Agent1
        vm.prank(agent2);
        uint256 sealId = sealRegistry.issueSealA2A(
            AGENT1_ID,
            SKILLFUL,
            88,
            EVIDENCE_HASH,
            0
        );

        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        assertEq(seal.subject, agent1);
        assertEq(seal.evaluator, agent2);
        assertEq(seal.sealType, SKILLFUL);
        assertEq(uint8(seal.quadrant), uint8(SealRegistry.Quadrant.A2A));
        assertEq(seal.score, 88);
        assertFalse(seal.revoked);
    }

    /// @dev Test A2A prevents self-evaluation
    function testIssueSealA2A_SelfEvaluation() public {
        vm.prank(agent1);
        vm.expectRevert(SealRegistry.SelfFeedbackNotAllowed.selector);
        sealRegistry.issueSealA2A(AGENT1_ID, SKILLFUL, 90, EVIDENCE_HASH, 0);
    }

    /// @dev Test A2A requires evaluator to be registered agent
    function testIssueSealA2A_NonAgentEvaluator() public {
        vm.prank(human1);
        vm.expectRevert(abi.encodeWithSelector(SealRegistry.AgentNotRegistered.selector, human1));
        sealRegistry.issueSealA2A(AGENT1_ID, SKILLFUL, 90, EVIDENCE_HASH, 0);
    }

    /// @dev Test A2A requires evaluator to have seal domain
    function testIssueSealA2A_UnauthorizedDomain() public {
        // Agent2 has no domains registered
        vm.prank(agent2);
        bytes32[] memory sealTypes = new bytes32[](1);
        sealTypes[0] = RELIABLE;
        sealRegistry.registerAgentSealDomains(sealTypes);

        // Try to issue SKILLFUL (not in agent2's domains)
        vm.prank(agent2);
        vm.expectRevert(abi.encodeWithSelector(
            SealRegistry.AgentNotAuthorizedForSealType.selector, agent2, SKILLFUL
        ));
        sealRegistry.issueSealA2A(AGENT1_ID, SKILLFUL, 90, EVIDENCE_HASH, 0);
    }

    /// @dev Test A2A with nonexistent subject agent
    function testIssueSealA2A_NonexistentSubject() public {
        vm.prank(agent1);
        vm.expectRevert(abi.encodeWithSelector(SealRegistry.AgentNotRegistered.selector, address(0)));
        sealRegistry.issueSealA2A(999, SKILLFUL, 90, EVIDENCE_HASH, 0);
    }

    /// @dev Test A2A with expiration
    function testIssueSealA2A_WithExpiration() public {
        // Register agent2
        vm.prank(agent2);
        bytes32[] memory sealTypes = new bytes32[](1);
        sealTypes[0] = SKILLFUL;
        sealRegistry.registerAgentSealDomains(sealTypes);

        uint48 expiresAt = uint48(block.timestamp + 1 days);

        vm.prank(agent2);
        uint256 sealId = sealRegistry.issueSealA2A(AGENT1_ID, SKILLFUL, 75, EVIDENCE_HASH, expiresAt);

        assertFalse(sealRegistry.isSealExpired(sealId));

        vm.warp(block.timestamp + 2 days);
        assertTrue(sealRegistry.isSealExpired(sealId));
    }

    /// @dev Test bidirectional A2A seals
    function testIssueSealA2A_Bidirectional() public {
        // Register both agents with SKILLFUL
        vm.prank(agent2);
        bytes32[] memory sealTypes = new bytes32[](1);
        sealTypes[0] = SKILLFUL;
        sealRegistry.registerAgentSealDomains(sealTypes);

        // Agent1 evaluates Agent2
        vm.prank(agent1);
        uint256 seal1 = sealRegistry.issueSealA2A(AGENT2_ID, SKILLFUL, 85, EVIDENCE_HASH, 0);

        // Agent2 evaluates Agent1
        vm.prank(agent2);
        uint256 seal2 = sealRegistry.issueSealA2A(AGENT1_ID, SKILLFUL, 90, EVIDENCE_HASH, 0);

        // Both seals exist with correct direction
        assertEq(sealRegistry.getSeal(seal1).subject, agent2);
        assertEq(sealRegistry.getSeal(seal1).evaluator, agent1);
        assertEq(sealRegistry.getSeal(seal2).subject, agent1);
        assertEq(sealRegistry.getSeal(seal2).evaluator, agent2);
    }

    // ============================================================
    // Batch Operations Tests
    // ============================================================

    /// @dev Test batch seal issuance (H2H)
    function testBatchIssueSeal_H2H() public {
        address[] memory subjects = new address[](3);
        subjects[0] = human2;
        subjects[1] = human2;
        subjects[2] = agent1;

        bytes32[] memory types = new bytes32[](3);
        types[0] = CREATIVE;
        types[1] = keccak256("PROFESSIONAL");
        types[2] = keccak256("FRIENDLY");

        SealRegistry.Quadrant[] memory quads = new SealRegistry.Quadrant[](3);
        quads[0] = SealRegistry.Quadrant.H2H;
        quads[1] = SealRegistry.Quadrant.H2H;
        quads[2] = SealRegistry.Quadrant.H2H;

        uint8[] memory scores = new uint8[](3);
        scores[0] = 85;
        scores[1] = 90;
        scores[2] = 77;

        bytes32[] memory evidences = new bytes32[](3);
        evidences[0] = keccak256("ev1");
        evidences[1] = keccak256("ev2");
        evidences[2] = keccak256("ev3");

        uint48[] memory expires = new uint48[](3);
        expires[0] = 0;
        expires[1] = 0;
        expires[2] = 0;

        vm.prank(human1);
        uint256[] memory sealIds = sealRegistry.batchIssueSeal(
            subjects, types, quads, scores, evidences, expires
        );

        assertEq(sealIds.length, 3);
        assertEq(sealRegistry.getSeal(sealIds[0]).score, 85);
        assertEq(sealRegistry.getSeal(sealIds[1]).score, 90);
        assertEq(sealRegistry.getSeal(sealIds[2]).score, 77);
    }

    /// @dev Test batch with agent quadrants (A2H)
    function testBatchIssueSeal_AgentQuadrant() public {
        address[] memory subjects = new address[](2);
        subjects[0] = human1;
        subjects[1] = human2;

        bytes32[] memory types = new bytes32[](2);
        types[0] = SKILLFUL;
        types[1] = RELIABLE;

        SealRegistry.Quadrant[] memory quads = new SealRegistry.Quadrant[](2);
        quads[0] = SealRegistry.Quadrant.A2H;
        quads[1] = SealRegistry.Quadrant.A2H;

        uint8[] memory scores = new uint8[](2);
        scores[0] = 92;
        scores[1] = 88;

        bytes32[] memory evidences = new bytes32[](2);
        evidences[0] = keccak256("task1");
        evidences[1] = keccak256("task2");

        uint48[] memory expires = new uint48[](2);
        expires[0] = 0;
        expires[1] = 0;

        vm.prank(agent1);
        uint256[] memory sealIds = sealRegistry.batchIssueSeal(
            subjects, types, quads, scores, evidences, expires
        );

        assertEq(sealIds.length, 2);
        assertEq(uint8(sealRegistry.getSeal(sealIds[0]).quadrant), uint8(SealRegistry.Quadrant.A2H));
        assertEq(uint8(sealRegistry.getSeal(sealIds[1]).quadrant), uint8(SealRegistry.Quadrant.A2H));
    }

    /// @dev Test batch with mismatched array lengths
    function testBatchIssueSeal_LengthMismatch() public {
        address[] memory subjects = new address[](2);
        subjects[0] = human1;
        subjects[1] = human2;

        bytes32[] memory types = new bytes32[](1); // Different length!
        types[0] = CREATIVE;

        SealRegistry.Quadrant[] memory quads = new SealRegistry.Quadrant[](2);
        quads[0] = SealRegistry.Quadrant.H2H;
        quads[1] = SealRegistry.Quadrant.H2H;

        uint8[] memory scores = new uint8[](2);
        scores[0] = 85;
        scores[1] = 90;

        bytes32[] memory evidences = new bytes32[](2);
        evidences[0] = EVIDENCE_HASH;
        evidences[1] = EVIDENCE_HASH;

        uint48[] memory expires = new uint48[](2);
        expires[0] = 0;
        expires[1] = 0;

        vm.prank(human1);
        vm.expectRevert(SealRegistry.BatchLengthMismatch.selector);
        sealRegistry.batchIssueSeal(subjects, types, quads, scores, evidences, expires);
    }

    /// @dev Test batch with empty arrays
    function testBatchIssueSeal_EmptyBatch() public {
        address[] memory subjects = new address[](0);
        bytes32[] memory types = new bytes32[](0);
        SealRegistry.Quadrant[] memory quads = new SealRegistry.Quadrant[](0);
        uint8[] memory scores = new uint8[](0);
        bytes32[] memory evidences = new bytes32[](0);
        uint48[] memory expires = new uint48[](0);

        vm.prank(human1);
        vm.expectRevert(abi.encodeWithSelector(SealRegistry.BatchSizeInvalid.selector, 0));
        sealRegistry.batchIssueSeal(subjects, types, quads, scores, evidences, expires);
    }

    // ============================================================
    // Composite Score Tests
    // ============================================================

    /// @dev Test composite score with multiple seals
    function testCompositeScore_Multiple() public {
        // Issue 3 H2H seals to human2 from human1
        vm.startPrank(human1);
        sealRegistry.issueSealH2H(human2, CREATIVE, 80, EVIDENCE_HASH);
        sealRegistry.issueSealH2H(human2, keccak256("PROFESSIONAL"), 90, EVIDENCE_HASH);
        sealRegistry.issueSealH2H(human2, keccak256("FRIENDLY"), 70, EVIDENCE_HASH);
        vm.stopPrank();

        // Composite: (80 + 90 + 70) / 3 = 80
        (uint256 avgScore, uint256 activeCount, uint256 totalCount) = 
            sealRegistry.compositeScore(human2, false, SealRegistry.Quadrant.H2H);
        assertEq(avgScore, 80);
        assertEq(activeCount, 3);
        assertEq(totalCount, 3);
    }

    /// @dev Test composite score excludes revoked seals
    function testCompositeScore_ExcludesRevoked() public {
        vm.startPrank(human1);
        uint256 seal1 = sealRegistry.issueSealH2H(human2, CREATIVE, 80, EVIDENCE_HASH);
        sealRegistry.issueSealH2H(human2, keccak256("PROFESSIONAL"), 100, EVIDENCE_HASH);
        sealRegistry.revokeSeal(seal1, "revoked");
        vm.stopPrank();

        // Only seal2 counts: 100/1 = 100
        (uint256 avgScore, uint256 activeCount, uint256 totalCount) = 
            sealRegistry.compositeScore(human2, false, SealRegistry.Quadrant.H2H);
        assertEq(avgScore, 100);
        assertEq(activeCount, 1);
        assertEq(totalCount, 2);
    }

    /// @dev Test composite score excludes expired seals
    function testCompositeScore_ExcludesExpired() public {
        uint48 soon = uint48(block.timestamp + 1 hours);

        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 50, EVIDENCE_HASH, soon);

        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, RELIABLE, 90, EVIDENCE_HASH, 0); // never expires

        // Before expiry: (50 + 90) / 2 = 70
        (uint256 avgBefore, uint256 countBefore,) = 
            sealRegistry.compositeScore(human1, false, SealRegistry.Quadrant.A2H);
        assertEq(avgBefore, 70);
        assertEq(countBefore, 2);

        // After expiry: only 90/1 = 90
        vm.warp(block.timestamp + 2 hours);
        (uint256 avgAfter, uint256 countAfter,) = 
            sealRegistry.compositeScore(human1, false, SealRegistry.Quadrant.A2H);
        assertEq(avgAfter, 90);
        assertEq(countAfter, 1);
    }

    /// @dev Test composite score with quadrant filter
    function testCompositeScore_QuadrantFilter() public {
        // Issue H2H seals
        vm.prank(human1);
        sealRegistry.issueSealH2H(human2, CREATIVE, 80, EVIDENCE_HASH);

        // Issue H2A seal to agent1 (human2 is subject for H2H only)
        // We'll check human2's score filtered by H2H
        (uint256 avgH2H, uint256 countH2H,) = 
            sealRegistry.compositeScore(human2, true, SealRegistry.Quadrant.H2H);
        assertEq(avgH2H, 80);
        assertEq(countH2H, 1);

        // Filter by A2H should return 0
        (uint256 avgA2H, uint256 countA2H,) = 
            sealRegistry.compositeScore(human2, true, SealRegistry.Quadrant.A2H);
        assertEq(avgA2H, 0);
        assertEq(countA2H, 0);
    }

    /// @dev Test composite score for address with no seals
    function testCompositeScore_NoSeals() public {
        address nobody = makeAddr("nobody");
        (uint256 avg, uint256 active, uint256 total) = 
            sealRegistry.compositeScore(nobody, false, SealRegistry.Quadrant.H2H);
        assertEq(avg, 0);
        assertEq(active, 0);
        assertEq(total, 0);
    }

    // ============================================================
    // Reputation By Type Tests
    // ============================================================

    /// @dev Test reputation by type
    function testReputationByType() public {
        vm.startPrank(human1);
        sealRegistry.issueSealH2H(human2, CREATIVE, 80, EVIDENCE_HASH);
        sealRegistry.issueSealH2H(human2, CREATIVE, 90, keccak256("ev2"));
        sealRegistry.issueSealH2H(human2, keccak256("PROFESSIONAL"), 70, keccak256("ev3"));
        vm.stopPrank();

        (uint256 avgCreative, uint256 countCreative) = sealRegistry.reputationByType(human2, CREATIVE);
        assertEq(avgCreative, 85); // (80+90)/2
        assertEq(countCreative, 2);

        (uint256 avgPro, uint256 countPro) = sealRegistry.reputationByType(human2, keccak256("PROFESSIONAL"));
        assertEq(avgPro, 70);
        assertEq(countPro, 1);
    }

    // ============================================================
    // Get Seals By Quadrant Tests
    // ============================================================

    /// @dev Test getting seals by quadrant
    function testGetSubjectSealsByQuadrant() public {
        // Issue seals in different quadrants for agent1
        vm.prank(human1);
        sealRegistry.issueSealH2A(AGENT1_ID, FAIR, 85, EVIDENCE_HASH);

        vm.prank(human2);
        sealRegistry.issueSealH2A(AGENT1_ID, FAIR, 90, keccak256("ev2"));

        vm.prank(human1);
        sealRegistry.issueSealH2H(agent1, CREATIVE, 70, keccak256("ev3"));

        // agent1 should have 2 H2A seals and 1 H2H seal
        uint256[] memory h2aSeals = sealRegistry.getSubjectSealsByQuadrant(agent1, SealRegistry.Quadrant.H2A);
        assertEq(h2aSeals.length, 2);

        uint256[] memory h2hSeals = sealRegistry.getSubjectSealsByQuadrant(agent1, SealRegistry.Quadrant.H2H);
        assertEq(h2hSeals.length, 1);

        uint256[] memory a2aSeals = sealRegistry.getSubjectSealsByQuadrant(agent1, SealRegistry.Quadrant.A2A);
        assertEq(a2aSeals.length, 0);
    }
}