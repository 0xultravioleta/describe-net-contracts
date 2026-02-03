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
}