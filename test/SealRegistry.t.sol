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
    // Batch Operations Tests (struct-based API)
    // ============================================================

    /// @dev Helper to create a BatchSealParams
    function _bp(
        address subject, bytes32 sealType, SealRegistry.Quadrant q,
        uint8 score, bytes32 ev, uint48 exp
    ) internal pure returns (SealRegistry.BatchSealParams memory) {
        return SealRegistry.BatchSealParams(subject, sealType, q, score, ev, exp);
    }

    /// @dev Test batch seal issuance (H2H)
    function testBatchIssueSeal_H2H() public {
        SealRegistry.BatchSealParams[] memory params = new SealRegistry.BatchSealParams[](3);
        params[0] = _bp(human2, CREATIVE, SealRegistry.Quadrant.H2H, 85, keccak256("ev1"), 0);
        params[1] = _bp(human2, keccak256("PROFESSIONAL"), SealRegistry.Quadrant.H2H, 90, keccak256("ev2"), 0);
        params[2] = _bp(agent1, keccak256("FRIENDLY"), SealRegistry.Quadrant.H2H, 77, keccak256("ev3"), 0);

        vm.prank(human1);
        uint256[] memory sealIds = sealRegistry.batchIssueSeal(params);

        assertEq(sealIds.length, 3);
        assertEq(sealRegistry.getSeal(sealIds[0]).score, 85);
        assertEq(sealRegistry.getSeal(sealIds[1]).score, 90);
        assertEq(sealRegistry.getSeal(sealIds[2]).score, 77);
    }

    /// @dev Test batch with agent quadrants (A2H)
    function testBatchIssueSeal_AgentQuadrant() public {
        SealRegistry.BatchSealParams[] memory params = new SealRegistry.BatchSealParams[](2);
        params[0] = _bp(human1, SKILLFUL, SealRegistry.Quadrant.A2H, 92, keccak256("task1"), 0);
        params[1] = _bp(human2, RELIABLE, SealRegistry.Quadrant.A2H, 88, keccak256("task2"), 0);

        vm.prank(agent1);
        uint256[] memory sealIds = sealRegistry.batchIssueSeal(params);

        assertEq(sealIds.length, 2);
        assertEq(uint8(sealRegistry.getSeal(sealIds[0]).quadrant), uint8(SealRegistry.Quadrant.A2H));
        assertEq(uint8(sealRegistry.getSeal(sealIds[1]).quadrant), uint8(SealRegistry.Quadrant.A2H));
    }

    /// @dev Test batch with empty arrays
    function testBatchIssueSeal_EmptyBatch() public {
        SealRegistry.BatchSealParams[] memory params = new SealRegistry.BatchSealParams[](0);

        vm.prank(human1);
        vm.expectRevert(abi.encodeWithSelector(SealRegistry.BatchSizeInvalid.selector, 0));
        sealRegistry.batchIssueSeal(params);
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

    // ============================================================
    //              DELEGATION SYSTEM TESTS
    // ============================================================

    /// @dev Test delegation grant and seal issuance by delegate (happy path)
    function testDelegation_HappyPath() public {
        address delegate1 = makeAddr("delegate1");
        
        // Agent1 delegates SKILLFUL and RELIABLE to delegate1
        vm.startPrank(agent1);
        bytes32[] memory delegatedTypes = new bytes32[](2);
        delegatedTypes[0] = SKILLFUL;
        delegatedTypes[1] = RELIABLE;
        sealRegistry.delegateSealAuthority(delegate1, delegatedTypes, 0); // never expires
        vm.stopPrank();
        
        // Verify delegation is active
        assertTrue(sealRegistry.isDelegationActive(agent1, delegate1));
        assertTrue(sealRegistry.isDelegateAuthorizedForType(agent1, delegate1, SKILLFUL));
        assertTrue(sealRegistry.isDelegateAuthorizedForType(agent1, delegate1, RELIABLE));
        assertFalse(sealRegistry.isDelegateAuthorizedForType(agent1, delegate1, FAIR));
        
        // Delegate1 issues seal as delegate of agent1
        vm.prank(delegate1);
        uint256 sealId = sealRegistry.issueSealAsDelegate(
            agent1, human1, SKILLFUL, SealRegistry.Quadrant.A2H, 85, EVIDENCE_HASH, 0
        );
        
        // Verify seal was created with delegate as evaluator
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        assertEq(seal.evaluator, delegate1);
        assertEq(seal.subject, human1);
        assertEq(seal.score, 85);
    }

    /// @dev Test delegation with expiration
    function testDelegation_Expiration() public {
        address delegate1 = makeAddr("delegate1");
        uint48 expiry = uint48(block.timestamp + 1 hours);
        
        vm.startPrank(agent1);
        bytes32[] memory delegatedTypes = new bytes32[](1);
        delegatedTypes[0] = SKILLFUL;
        sealRegistry.delegateSealAuthority(delegate1, delegatedTypes, expiry);
        vm.stopPrank();
        
        // Before expiry: works
        assertTrue(sealRegistry.isDelegationActive(agent1, delegate1));
        
        // After expiry: fails
        vm.warp(block.timestamp + 2 hours);
        assertFalse(sealRegistry.isDelegationActive(agent1, delegate1));
        
        // Trying to issue seal as expired delegate should revert
        vm.prank(delegate1);
        vm.expectRevert(SealRegistry.DelegationNotActive.selector);
        sealRegistry.issueSealAsDelegate(
            agent1, human1, SKILLFUL, SealRegistry.Quadrant.A2H, 85, EVIDENCE_HASH, 0
        );
    }

    /// @dev Test delegation revocation
    function testDelegation_Revocation() public {
        address delegate1 = makeAddr("delegate1");
        
        vm.startPrank(agent1);
        bytes32[] memory delegatedTypes = new bytes32[](1);
        delegatedTypes[0] = SKILLFUL;
        sealRegistry.delegateSealAuthority(delegate1, delegatedTypes, 0);
        
        // Verify active
        assertTrue(sealRegistry.isDelegationActive(agent1, delegate1));
        
        // Revoke
        sealRegistry.revokeDelegation(delegate1);
        vm.stopPrank();
        
        assertFalse(sealRegistry.isDelegationActive(agent1, delegate1));
        
        // Try to issue seal → should fail
        vm.prank(delegate1);
        vm.expectRevert(SealRegistry.DelegationNotActive.selector);
        sealRegistry.issueSealAsDelegate(
            agent1, human1, SKILLFUL, SealRegistry.Quadrant.A2H, 85, EVIDENCE_HASH, 0
        );
    }

    /// @dev Test self-delegation is not allowed
    function testDelegation_SelfNotAllowed() public {
        vm.startPrank(agent1);
        bytes32[] memory delegatedTypes = new bytes32[](1);
        delegatedTypes[0] = SKILLFUL;
        
        vm.expectRevert(SealRegistry.SelfDelegationNotAllowed.selector);
        sealRegistry.delegateSealAuthority(agent1, delegatedTypes, 0);
        vm.stopPrank();
    }

    /// @dev Test non-agent cannot delegate
    function testDelegation_NonAgentCannotDelegate() public {
        vm.startPrank(human1);
        bytes32[] memory delegatedTypes = new bytes32[](1);
        delegatedTypes[0] = SKILLFUL;
        
        vm.expectRevert(abi.encodeWithSelector(SealRegistry.AgentNotRegistered.selector, human1));
        sealRegistry.delegateSealAuthority(makeAddr("del"), delegatedTypes, 0);
        vm.stopPrank();
    }

    /// @dev Test cannot delegate seal types not in own domains
    function testDelegation_CannotDelegateUnauthorizedTypes() public {
        // Agent1 only has SKILLFUL, RELIABLE, THOROUGH — not FAIR
        vm.startPrank(agent1);
        bytes32[] memory delegatedTypes = new bytes32[](1);
        delegatedTypes[0] = FAIR;
        
        vm.expectRevert(abi.encodeWithSelector(
            SealRegistry.AgentNotAuthorizedForSealType.selector, agent1, FAIR
        ));
        sealRegistry.delegateSealAuthority(makeAddr("del"), delegatedTypes, 0);
        vm.stopPrank();
    }

    /// @dev Test delegate cannot issue unauthorized seal type
    function testDelegation_DelegateUnauthorizedType() public {
        address delegate1 = makeAddr("delegate1");
        
        // Delegate only SKILLFUL
        vm.startPrank(agent1);
        bytes32[] memory delegatedTypes = new bytes32[](1);
        delegatedTypes[0] = SKILLFUL;
        sealRegistry.delegateSealAuthority(delegate1, delegatedTypes, 0);
        vm.stopPrank();
        
        // Try issuing RELIABLE (not delegated)
        vm.prank(delegate1);
        vm.expectRevert(abi.encodeWithSelector(
            SealRegistry.DelegateNotAuthorizedForSealType.selector, delegate1, RELIABLE
        ));
        sealRegistry.issueSealAsDelegate(
            agent1, human1, RELIABLE, SealRegistry.Quadrant.A2H, 85, EVIDENCE_HASH, 0
        );
    }

    /// @dev Test revoking non-existent delegation
    function testDelegation_RevokeNonExistent() public {
        vm.prank(agent1);
        vm.expectRevert(SealRegistry.DelegationNotActive.selector);
        sealRegistry.revokeDelegation(makeAddr("nobody"));
    }

    // ============================================================
    //          EIP-712 META-TRANSACTION TESTS
    // ============================================================

    /// @dev Helper: create a private key and corresponding address
    uint256 constant SIGNER_PK = 0xBEEF;
    address signerAddr; // set in setUp or test
    
    /// @dev Helper: sign a MetaTxParams struct using EIP-712
    function _signMetaTx(
        SealRegistry.MetaTxParams memory params,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(
            sealRegistry.SEAL_TYPEHASH(),
            params.subject,
            params.sealType,
            params.quadrant,
            params.score,
            params.evidenceHash,
            params.expiresAt,
            params.nonce,
            params.deadline
        ));
        
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            sealRegistry.DOMAIN_SEPARATOR(),
            structHash
        ));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Test meta-transaction seal submission (H2H, happy path)
    function testMetaTx_H2H_HappyPath() public {
        uint256 pk = 0xA11CE;
        address signer = vm.addr(pk);
        
        SealRegistry.MetaTxParams memory params = SealRegistry.MetaTxParams({
            subject: human2,
            sealType: CREATIVE,
            quadrant: uint8(SealRegistry.Quadrant.H2H),
            score: 88,
            evidenceHash: EVIDENCE_HASH,
            expiresAt: 0,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });
        
        bytes memory sig = _signMetaTx(params, pk);
        
        // Anyone (relayer) can submit
        vm.prank(human1);
        uint256 sealId = sealRegistry.submitSealWithSignature(params, sig);
        
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        assertEq(seal.evaluator, signer);
        assertEq(seal.subject, human2);
        assertEq(seal.score, 88);
        assertEq(uint8(seal.quadrant), uint8(SealRegistry.Quadrant.H2H));
        
        // Nonce should be incremented
        assertEq(sealRegistry.nonces(signer), 1);
    }

    /// @dev Test meta-transaction for agent quadrant (A2H)
    function testMetaTx_A2H_AgentSeal() public {
        // Use agent1's actual private key — we need to set one up
        uint256 agentPk = 0xA6E1;
        address agentSigner = vm.addr(agentPk);
        
        // Register this signer as an agent
        vm.prank(owner);
        identityRegistry.addAgent(100, "metatx-agent.com", agentSigner);
        
        // Register seal domains
        vm.startPrank(agentSigner);
        bytes32[] memory domains = new bytes32[](1);
        domains[0] = SKILLFUL;
        sealRegistry.registerAgentSealDomains(domains);
        vm.stopPrank();
        
        SealRegistry.MetaTxParams memory params = SealRegistry.MetaTxParams({
            subject: human1,
            sealType: SKILLFUL,
            quadrant: uint8(SealRegistry.Quadrant.A2H),
            score: 95,
            evidenceHash: EVIDENCE_HASH,
            expiresAt: 0,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });
        
        bytes memory sig = _signMetaTx(params, agentPk);
        
        // Relayer submits
        vm.prank(human2);
        uint256 sealId = sealRegistry.submitSealWithSignature(params, sig);
        
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);
        assertEq(seal.evaluator, agentSigner);
        assertEq(seal.score, 95);
        assertEq(uint8(seal.quadrant), uint8(SealRegistry.Quadrant.A2H));
    }

    /// @dev Test meta-transaction with expired deadline
    function testMetaTx_ExpiredDeadline() public {
        uint256 pk = 0xA11CE;
        
        SealRegistry.MetaTxParams memory params = SealRegistry.MetaTxParams({
            subject: human2,
            sealType: CREATIVE,
            quadrant: uint8(SealRegistry.Quadrant.H2H),
            score: 80,
            evidenceHash: EVIDENCE_HASH,
            expiresAt: 0,
            nonce: 0,
            deadline: block.timestamp - 1 // already expired
        });
        
        bytes memory sig = _signMetaTx(params, pk);
        
        vm.expectRevert(SealRegistry.DeadlineExpired.selector);
        sealRegistry.submitSealWithSignature(params, sig);
    }

    /// @dev Test meta-transaction with wrong nonce
    function testMetaTx_WrongNonce() public {
        uint256 pk = 0xA11CE;
        
        SealRegistry.MetaTxParams memory params = SealRegistry.MetaTxParams({
            subject: human2,
            sealType: CREATIVE,
            quadrant: uint8(SealRegistry.Quadrant.H2H),
            score: 80,
            evidenceHash: EVIDENCE_HASH,
            expiresAt: 0,
            nonce: 99, // wrong nonce
            deadline: block.timestamp + 1 hours
        });
        
        bytes memory sig = _signMetaTx(params, pk);
        
        vm.expectRevert(SealRegistry.InvalidNonce.selector);
        sealRegistry.submitSealWithSignature(params, sig);
    }

    /// @dev Test meta-transaction nonce increments correctly (replay protection)
    function testMetaTx_NonceReplayProtection() public {
        uint256 pk = 0xA11CE;
        address signer = vm.addr(pk);
        
        // First submission (nonce 0)
        SealRegistry.MetaTxParams memory params1 = SealRegistry.MetaTxParams({
            subject: human2,
            sealType: CREATIVE,
            quadrant: uint8(SealRegistry.Quadrant.H2H),
            score: 80,
            evidenceHash: EVIDENCE_HASH,
            expiresAt: 0,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });
        bytes memory sig1 = _signMetaTx(params1, pk);
        sealRegistry.submitSealWithSignature(params1, sig1);
        assertEq(sealRegistry.nonces(signer), 1);
        
        // Replay same signature → fails (nonce already used)
        vm.expectRevert(SealRegistry.InvalidNonce.selector);
        sealRegistry.submitSealWithSignature(params1, sig1);
        
        // Second submission (nonce 1) works
        SealRegistry.MetaTxParams memory params2 = SealRegistry.MetaTxParams({
            subject: human2,
            sealType: CREATIVE,
            quadrant: uint8(SealRegistry.Quadrant.H2H),
            score: 90,
            evidenceHash: keccak256("ev2"),
            expiresAt: 0,
            nonce: 1,
            deadline: block.timestamp + 1 hours
        });
        bytes memory sig2 = _signMetaTx(params2, pk);
        sealRegistry.submitSealWithSignature(params2, sig2);
        assertEq(sealRegistry.nonces(signer), 2);
    }

    /// @dev Test meta-transaction A2H requires registered agent
    function testMetaTx_A2H_NonAgentReverts() public {
        uint256 pk = 0xDEAD; // not registered as agent
        address signer = vm.addr(pk);
        
        SealRegistry.MetaTxParams memory params = SealRegistry.MetaTxParams({
            subject: human1,
            sealType: SKILLFUL,
            quadrant: uint8(SealRegistry.Quadrant.A2H),
            score: 80,
            evidenceHash: EVIDENCE_HASH,
            expiresAt: 0,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });
        
        bytes memory sig = _signMetaTx(params, pk);
        
        vm.expectRevert(abi.encodeWithSelector(SealRegistry.AgentNotRegistered.selector, signer));
        sealRegistry.submitSealWithSignature(params, sig);
    }

    /// @dev Test batch meta-transaction submission
    function testMetaTx_Batch() public {
        uint256 pk1 = 0xA11CE;
        uint256 pk2 = 0xB0B;
        
        SealRegistry.MetaTxParams[] memory params = new SealRegistry.MetaTxParams[](2);
        bytes[] memory sigs = new bytes[](2);
        
        params[0] = SealRegistry.MetaTxParams({
            subject: human2,
            sealType: CREATIVE,
            quadrant: uint8(SealRegistry.Quadrant.H2H),
            score: 80,
            evidenceHash: EVIDENCE_HASH,
            expiresAt: 0,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });
        sigs[0] = _signMetaTx(params[0], pk1);
        
        params[1] = SealRegistry.MetaTxParams({
            subject: human1,
            sealType: keccak256("PROFESSIONAL"),
            quadrant: uint8(SealRegistry.Quadrant.H2H),
            score: 95,
            evidenceHash: keccak256("ev2"),
            expiresAt: 0,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });
        sigs[1] = _signMetaTx(params[1], pk2);
        
        uint256[] memory sealIds = sealRegistry.batchSubmitSealsWithSignatures(params, sigs);
        
        assertEq(sealIds.length, 2);
        assertEq(sealRegistry.getSeal(sealIds[0]).score, 80);
        assertEq(sealRegistry.getSeal(sealIds[1]).score, 95);
    }

    /// @dev Test DOMAIN_SEPARATOR is accessible
    function testMetaTx_DomainSeparator() public view {
        bytes32 ds = sealRegistry.DOMAIN_SEPARATOR();
        assertTrue(ds != bytes32(0));
    }

    // ============================================================
    //          TIME-WEIGHTED SCORING TESTS
    // ============================================================

    /// @dev Test time-weighted score with recent vs old seals
    function testTimeWeighted_RecentVsOld() public {
        uint256 halfLife = 30 days;
        
        // Issue old seal (60 days ago worth of time)
        vm.prank(human1);
        sealRegistry.issueSealH2H(human2, CREATIVE, 40, EVIDENCE_HASH);
        
        // Warp 60 days
        vm.warp(block.timestamp + 60 days);
        
        // Issue recent seal (now)
        vm.prank(human1);
        sealRegistry.issueSealH2H(human2, keccak256("PROFESSIONAL"), 100, keccak256("ev2"));
        
        // Time-weighted score should favor the recent seal (100) over the old one (40)
        (uint256 weighted, uint256 count) = sealRegistry.timeWeightedScore(
            human2, halfLife, false, SealRegistry.Quadrant.H2H
        );
        
        assertEq(count, 2);
        // Old seal: weight = 30d/(30d+60d) = 30/90 = 0.333, score contribution = 40*0.333 = 13.33
        // New seal: weight = 30d/(30d+0d) = 30/30 = 1.0, score contribution = 100*1.0 = 100
        // Weighted avg = (13.33 + 100) / (0.333 + 1.0) = 113.33 / 1.333 ≈ 85
        assertTrue(weighted > 80 && weighted < 90, "Should favor recent seal");
    }

    /// @dev Test time-weighted score with all-same-age seals equals simple average
    function testTimeWeighted_SameAge() public {
        uint256 halfLife = 30 days;
        
        vm.startPrank(human1);
        sealRegistry.issueSealH2H(human2, CREATIVE, 80, EVIDENCE_HASH);
        sealRegistry.issueSealH2H(human2, keccak256("PROFESSIONAL"), 90, keccak256("ev2"));
        sealRegistry.issueSealH2H(human2, keccak256("FRIENDLY"), 70, keccak256("ev3"));
        vm.stopPrank();
        
        // All same timestamp → equal weights → simple average = (80+90+70)/3 = 80
        (uint256 weighted, uint256 count) = sealRegistry.timeWeightedScore(
            human2, halfLife, false, SealRegistry.Quadrant.H2H
        );
        
        assertEq(count, 3);
        assertEq(weighted, 80);
    }

    /// @dev Test time-weighted score excludes revoked seals
    function testTimeWeighted_ExcludesRevoked() public {
        vm.startPrank(human1);
        uint256 seal1 = sealRegistry.issueSealH2H(human2, CREATIVE, 40, EVIDENCE_HASH);
        sealRegistry.issueSealH2H(human2, keccak256("PROFESSIONAL"), 100, keccak256("ev2"));
        sealRegistry.revokeSeal(seal1, "wrong");
        vm.stopPrank();
        
        (uint256 weighted, uint256 count) = sealRegistry.timeWeightedScore(
            human2, 30 days, false, SealRegistry.Quadrant.H2H
        );
        
        assertEq(count, 1);
        assertEq(weighted, 100); // only non-revoked seal
    }

    /// @dev Test time-weighted score excludes expired seals
    function testTimeWeighted_ExcludesExpired() public {
        uint48 soon = uint48(block.timestamp + 1 hours);
        
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 50, EVIDENCE_HASH, soon);
        
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, RELIABLE, 100, keccak256("ev2"), 0);
        
        vm.warp(block.timestamp + 2 hours);
        
        (uint256 weighted, uint256 count) = sealRegistry.timeWeightedScore(
            human1, 30 days, false, SealRegistry.Quadrant.A2H
        );
        
        assertEq(count, 1);
        assertEq(weighted, 100);
    }

    /// @dev Test time-weighted score with quadrant filter
    function testTimeWeighted_QuadrantFilter() public {
        vm.prank(human1);
        sealRegistry.issueSealH2H(human2, CREATIVE, 80, EVIDENCE_HASH);
        
        vm.prank(human1);
        sealRegistry.issueSealH2A(AGENT2_ID, FAIR, 60, keccak256("ev2"));
        
        // Filter H2H → should only see the 80 score seal
        (uint256 weightedH2H, uint256 countH2H) = sealRegistry.timeWeightedScore(
            human2, 30 days, true, SealRegistry.Quadrant.H2H
        );
        assertEq(countH2H, 1);
        assertEq(weightedH2H, 80);
        
        // Filter A2H → should see nothing for human2
        (uint256 weightedA2H, uint256 countA2H) = sealRegistry.timeWeightedScore(
            human2, 30 days, true, SealRegistry.Quadrant.A2H
        );
        assertEq(countA2H, 0);
        assertEq(weightedA2H, 0);
    }

    /// @dev Test time-weighted score with no seals
    function testTimeWeighted_NoSeals() public {
        address nobody = makeAddr("nobody");
        (uint256 weighted, uint256 count) = sealRegistry.timeWeightedScore(
            nobody, 30 days, false, SealRegistry.Quadrant.H2H
        );
        assertEq(weighted, 0);
        assertEq(count, 0);
    }

    /// @dev Test time-weighted score with very short half-life (aggressive decay)
    function testTimeWeighted_ShortHalfLife() public {
        vm.prank(human1);
        sealRegistry.issueSealH2H(human2, CREATIVE, 50, EVIDENCE_HASH);
        
        // Warp 365 days
        vm.warp(block.timestamp + 365 days);
        
        // Issue new seal
        vm.prank(human1);
        sealRegistry.issueSealH2H(human2, keccak256("PROFESSIONAL"), 100, keccak256("ev2"));
        
        // With 1-day half-life, old seal is almost worthless
        (uint256 weighted, uint256 count) = sealRegistry.timeWeightedScore(
            human2, 1 days, false, SealRegistry.Quadrant.H2H
        );
        
        assertEq(count, 2);
        // Old seal weight: 1/(1+365) ≈ 0.0027, basically nothing
        // New seal weight: 1/(1+0) = 1.0
        // Result should be very close to 100
        assertTrue(weighted >= 99, "Old seal should be nearly worthless with short half-life");
    }
}