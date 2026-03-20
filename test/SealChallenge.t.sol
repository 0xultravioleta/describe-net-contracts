// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SealRegistry.sol";
import "../src/SealChallenge.sol";
import "../src/mocks/MockIdentityRegistry.sol";

contract SealChallengeTest is Test {
    SealRegistry public registry;
    SealChallenge public challenge;
    MockIdentityRegistry public identityRegistry;

    address public owner = address(this);
    address public evaluator = address(0x1);
    address public subject = address(0x2);
    address public resolver = address(0x3);
    address public stranger = address(0x4);

    bytes32 public constant SKILLFUL = keccak256("SKILLFUL");
    bytes32 public constant RELIABLE = keccak256("RELIABLE");
    bytes32 public constant EVIDENCE_HASH = keccak256("evidence");
    bytes32 public constant CHALLENGE_EVIDENCE = keccak256("challenge-evidence");

    function setUp() public {
        // Deploy identity registry mock
        identityRegistry = new MockIdentityRegistry();
        identityRegistry.addAgent(1, "evaluator.agent", evaluator);
        identityRegistry.addAgent(2, "subject.agent", subject);

        // Deploy seal registry
        registry = new SealRegistry(address(identityRegistry));

        // Register valid seal types
        registry.addSealType(SKILLFUL);
        registry.addSealType(RELIABLE);

        // Authorize evaluator to issue these seal types
        bytes32[] memory types = new bytes32[](2);
        types[0] = SKILLFUL;
        types[1] = RELIABLE;
        vm.prank(evaluator);
        registry.registerAgentSealDomains(types);

        // Deploy challenge contract
        challenge = new SealChallenge(address(registry));

        // Set challenge contract as authorized revoker
        registry.setChallengeRevoker(address(challenge));

        // Grant resolver role
        challenge.grantRole(challenge.RESOLVER_ROLE(), resolver);
    }

    // ─── Helper: Issue a seal and return its ID ──────────────────────

    function _issueSeal() internal returns (uint256) {
        vm.prank(evaluator);
        return registry.issueSealA2H(
            subject,
            SKILLFUL,
            80,
            EVIDENCE_HASH,
            0 // no expiry
        );
    }

    function _issueSealWithExpiry(uint48 expiresAt) internal returns (uint256) {
        vm.prank(evaluator);
        return registry.issueSealA2H(
            subject,
            RELIABLE,
            90,
            EVIDENCE_HASH,
            expiresAt
        );
    }

    // ═══════════════════════════════════════════════════════════════
    //  CHALLENGE CREATION
    // ═══════════════════════════════════════════════════════════════

    function testCreateChallenge() public {
        uint256 sealId = _issueSeal();

        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(
            sealId,
            "Rating is unfair - evidence does not match",
            CHALLENGE_EVIDENCE
        );

        ISealChallenge.Challenge memory c = challenge.getChallenge(challengeId);
        assertEq(c.sealId, sealId);
        assertEq(c.challenger, subject);
        assertEq(c.reason, "Rating is unfair - evidence does not match");
        assertEq(c.evidenceHash, CHALLENGE_EVIDENCE);
        assertEq(uint8(c.status), uint8(ISealChallenge.ChallengeStatus.Pending));
        assertTrue(c.deadline > c.createdAt);
    }

    function testCreateChallengeEmitsEvent() public {
        uint256 sealId = _issueSeal();

        vm.prank(subject);
        vm.expectEmit(true, true, true, true);
        emit ISealChallenge.ChallengeCreated(
            0, sealId, subject, "Unfair seal"
        );
        challenge.createChallenge(sealId, "Unfair seal", CHALLENGE_EVIDENCE);
    }

    function testCannotChallengeOthersSeal() public {
        uint256 sealId = _issueSeal();

        vm.prank(stranger);
        vm.expectRevert("SealChallenge: not subject");
        challenge.createChallenge(sealId, "Not my seal", CHALLENGE_EVIDENCE);
    }

    function testCannotChallengeRevokedSeal() public {
        uint256 sealId = _issueSeal();

        // Evaluator revokes their own seal
        vm.prank(evaluator);
        registry.revokeSeal(sealId, "self-revocation");

        vm.prank(subject);
        vm.expectRevert("SealChallenge: already revoked");
        challenge.createChallenge(sealId, "Too late", CHALLENGE_EVIDENCE);
    }

    function testCannotChallengeExpiredSeal() public {
        uint256 sealId = _issueSealWithExpiry(uint48(block.timestamp + 1 hours));

        // Warp past expiry
        vm.warp(block.timestamp + 2 hours);

        vm.prank(subject);
        vm.expectRevert("SealChallenge: seal expired");
        challenge.createChallenge(sealId, "Expired", CHALLENGE_EVIDENCE);
    }

    function testCannotCreateEmptyReason() public {
        uint256 sealId = _issueSeal();

        vm.prank(subject);
        vm.expectRevert("SealChallenge: empty reason");
        challenge.createChallenge(sealId, "", CHALLENGE_EVIDENCE);
    }

    function testCannotCreateTooLongReason() public {
        uint256 sealId = _issueSeal();

        // Create a string longer than MAX_REASON_LENGTH (1000)
        bytes memory longReason = new bytes(1001);
        for (uint i = 0; i < 1001; i++) {
            longReason[i] = "A";
        }

        vm.prank(subject);
        vm.expectRevert("SealChallenge: reason too long");
        challenge.createChallenge(sealId, string(longReason), CHALLENGE_EVIDENCE);
    }

    function testCannotDuplicateActiveChallenge() public {
        uint256 sealId = _issueSeal();

        vm.startPrank(subject);
        challenge.createChallenge(sealId, "First challenge", CHALLENGE_EVIDENCE);

        vm.expectRevert("SealChallenge: active challenge exists");
        challenge.createChallenge(sealId, "Second challenge", CHALLENGE_EVIDENCE);
        vm.stopPrank();
    }

    function testCanRechallengeAfterResolution() public {
        uint256 sealId = _issueSeal();

        // First challenge
        vm.prank(subject);
        uint256 c1 = challenge.createChallenge(sealId, "First", CHALLENGE_EVIDENCE);

        // Reject it
        vm.prank(resolver);
        challenge.resolveChallenge(c1, ISealChallenge.ChallengeStatus.Rejected, "Not valid");

        // Can challenge again
        vm.prank(subject);
        uint256 c2 = challenge.createChallenge(sealId, "Second attempt", CHALLENGE_EVIDENCE);
        assertEq(c2, 1);
    }

    // ═══════════════════════════════════════════════════════════════
    //  CHALLENGE RESOLUTION
    // ═══════════════════════════════════════════════════════════════

    function testResolveSustained() public {
        uint256 sealId = _issueSeal();

        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(sealId, "Unfair", CHALLENGE_EVIDENCE);

        vm.prank(resolver);
        challenge.resolveChallenge(
            challengeId,
            ISealChallenge.ChallengeStatus.Sustained,
            "Challenge upheld - evidence supports claim"
        );

        ISealChallenge.Challenge memory c = challenge.getChallenge(challengeId);
        assertEq(uint8(c.status), uint8(ISealChallenge.ChallengeStatus.Sustained));
        assertEq(c.resolver, resolver);
        assertTrue(c.resolvedAt > 0);

        // Seal should be revoked in registry
        SealRegistry.Seal memory seal = registry.getSeal(sealId);
        assertTrue(seal.revoked);
    }

    function testResolveRejected() public {
        uint256 sealId = _issueSeal();

        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(sealId, "Unfair", CHALLENGE_EVIDENCE);

        vm.prank(resolver);
        challenge.resolveChallenge(
            challengeId,
            ISealChallenge.ChallengeStatus.Rejected,
            "Original evaluation is accurate"
        );

        ISealChallenge.Challenge memory c = challenge.getChallenge(challengeId);
        assertEq(uint8(c.status), uint8(ISealChallenge.ChallengeStatus.Rejected));

        // Seal should NOT be revoked
        SealRegistry.Seal memory seal = registry.getSeal(sealId);
        assertFalse(seal.revoked);
    }

    function testResolveEmitsEvent() public {
        uint256 sealId = _issueSeal();
        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(sealId, "Test", CHALLENGE_EVIDENCE);

        vm.prank(resolver);
        vm.expectEmit(true, false, false, true);
        emit ISealChallenge.ChallengeResolved(
            challengeId,
            ISealChallenge.ChallengeStatus.Sustained,
            resolver,
            "Upheld"
        );
        challenge.resolveChallenge(
            challengeId,
            ISealChallenge.ChallengeStatus.Sustained,
            "Upheld"
        );
    }

    function testCannotResolveNonPending() public {
        uint256 sealId = _issueSeal();
        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(sealId, "Test", CHALLENGE_EVIDENCE);

        // Resolve once
        vm.prank(resolver);
        challenge.resolveChallenge(challengeId, ISealChallenge.ChallengeStatus.Rejected, "No");

        // Try to resolve again
        vm.prank(resolver);
        vm.expectRevert("SealChallenge: not pending");
        challenge.resolveChallenge(challengeId, ISealChallenge.ChallengeStatus.Sustained, "Wait");
    }

    function testCannotResolveWithInvalidStatus() public {
        uint256 sealId = _issueSeal();
        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(sealId, "Test", CHALLENGE_EVIDENCE);

        vm.prank(resolver);
        vm.expectRevert("SealChallenge: invalid status");
        challenge.resolveChallenge(challengeId, ISealChallenge.ChallengeStatus.Pending, "Bad");
    }

    function testEvaluatorCannotBeResolver() public {
        uint256 sealId = _issueSeal();
        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(sealId, "Test", CHALLENGE_EVIDENCE);

        // Grant evaluator the resolver role
        challenge.grantRole(challenge.RESOLVER_ROLE(), evaluator);

        // Evaluator tries to resolve their own seal's challenge — conflict of interest
        vm.prank(evaluator);
        vm.expectRevert("SealChallenge: resolver is evaluator");
        challenge.resolveChallenge(challengeId, ISealChallenge.ChallengeStatus.Rejected, "I'm fair");
    }

    function testNonResolverCannotResolve() public {
        uint256 sealId = _issueSeal();
        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(sealId, "Test", CHALLENGE_EVIDENCE);

        vm.prank(stranger);
        vm.expectRevert(); // AccessControl revert
        challenge.resolveChallenge(challengeId, ISealChallenge.ChallengeStatus.Rejected, "No");
    }

    // ═══════════════════════════════════════════════════════════════
    //  CHALLENGE WITHDRAWAL
    // ═══════════════════════════════════════════════════════════════

    function testWithdrawChallenge() public {
        uint256 sealId = _issueSeal();
        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(sealId, "Changed my mind", CHALLENGE_EVIDENCE);

        vm.prank(subject);
        challenge.withdrawChallenge(challengeId);

        ISealChallenge.Challenge memory c = challenge.getChallenge(challengeId);
        assertEq(uint8(c.status), uint8(ISealChallenge.ChallengeStatus.Withdrawn));

        // Seal should NOT be revoked
        SealRegistry.Seal memory seal = registry.getSeal(sealId);
        assertFalse(seal.revoked);
    }

    function testWithdrawEmitsEvent() public {
        uint256 sealId = _issueSeal();
        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(sealId, "Test", CHALLENGE_EVIDENCE);

        vm.prank(subject);
        vm.expectEmit(true, true, false, false);
        emit ISealChallenge.ChallengeWithdrawn(challengeId, subject);
        challenge.withdrawChallenge(challengeId);
    }

    function testCannotWithdrawOthersChallenge() public {
        uint256 sealId = _issueSeal();
        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(sealId, "Test", CHALLENGE_EVIDENCE);

        vm.prank(stranger);
        vm.expectRevert("SealChallenge: not challenger");
        challenge.withdrawChallenge(challengeId);
    }

    function testCannotWithdrawResolvedChallenge() public {
        uint256 sealId = _issueSeal();
        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(sealId, "Test", CHALLENGE_EVIDENCE);

        vm.prank(resolver);
        challenge.resolveChallenge(challengeId, ISealChallenge.ChallengeStatus.Rejected, "No");

        vm.prank(subject);
        vm.expectRevert("SealChallenge: not pending");
        challenge.withdrawChallenge(challengeId);
    }

    function testCanRechallengeAfterWithdrawal() public {
        uint256 sealId = _issueSeal();

        vm.startPrank(subject);
        uint256 c1 = challenge.createChallenge(sealId, "First", CHALLENGE_EVIDENCE);
        challenge.withdrawChallenge(c1);

        // Can create new challenge after withdrawal
        uint256 c2 = challenge.createChallenge(sealId, "Second", CHALLENGE_EVIDENCE);
        assertEq(c2, 1);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════
    //  CHALLENGE EXPIRY
    // ═══════════════════════════════════════════════════════════════

    function testExpireChallenge() public {
        uint256 sealId = _issueSeal();
        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(sealId, "Test", CHALLENGE_EVIDENCE);

        // Warp past deadline (7 days default)
        vm.warp(block.timestamp + 7 days + 1);

        challenge.expireChallenge(challengeId);

        ISealChallenge.Challenge memory c = challenge.getChallenge(challengeId);
        assertEq(uint8(c.status), uint8(ISealChallenge.ChallengeStatus.Expired));
    }

    function testCannotExpireBeforeDeadline() public {
        uint256 sealId = _issueSeal();
        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(sealId, "Test", CHALLENGE_EVIDENCE);

        // Try to expire before deadline
        vm.warp(block.timestamp + 3 days);
        vm.expectRevert("SealChallenge: not expired yet");
        challenge.expireChallenge(challengeId);
    }

    function testAnyoneCanCallExpire() public {
        uint256 sealId = _issueSeal();
        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(sealId, "Test", CHALLENGE_EVIDENCE);

        vm.warp(block.timestamp + 7 days + 1);

        // Stranger can expire it (public good)
        vm.prank(stranger);
        challenge.expireChallenge(challengeId);

        ISealChallenge.Challenge memory c = challenge.getChallenge(challengeId);
        assertEq(uint8(c.status), uint8(ISealChallenge.ChallengeStatus.Expired));
    }

    function testCanRechallengeAfterExpiry() public {
        uint256 sealId = _issueSeal();

        vm.prank(subject);
        uint256 c1 = challenge.createChallenge(sealId, "First", CHALLENGE_EVIDENCE);

        vm.warp(block.timestamp + 7 days + 1);
        challenge.expireChallenge(c1);

        vm.prank(subject);
        uint256 c2 = challenge.createChallenge(sealId, "Second try", CHALLENGE_EVIDENCE);
        assertEq(c2, 1);
    }

    // ═══════════════════════════════════════════════════════════════
    //  VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    function testGetChallengesForSeal() public {
        uint256 sealId = _issueSeal();

        // Issue second seal for same subject
        vm.prank(evaluator);
        uint256 sealId2 = registry.issueSealA2H(
            subject, RELIABLE, 70, EVIDENCE_HASH, 0
        );

        // Challenge both
        vm.startPrank(subject);
        challenge.createChallenge(sealId, "Challenge 1", CHALLENGE_EVIDENCE);
        challenge.createChallenge(sealId2, "Challenge 2", CHALLENGE_EVIDENCE);
        vm.stopPrank();

        uint256[] memory seal1Challenges = challenge.getChallengesForSeal(sealId);
        assertEq(seal1Challenges.length, 1);
        assertEq(seal1Challenges[0], 0);

        uint256[] memory seal2Challenges = challenge.getChallengesForSeal(sealId2);
        assertEq(seal2Challenges.length, 1);
        assertEq(seal2Challenges[0], 1);
    }

    function testGetChallengesByChallenger() public {
        uint256 sealId = _issueSeal();
        vm.prank(evaluator);
        uint256 sealId2 = registry.issueSealA2H(
            subject, RELIABLE, 70, EVIDENCE_HASH, 0
        );

        vm.startPrank(subject);
        challenge.createChallenge(sealId, "C1", CHALLENGE_EVIDENCE);
        challenge.createChallenge(sealId2, "C2", CHALLENGE_EVIDENCE);
        vm.stopPrank();

        uint256[] memory challenges = challenge.getChallengesByChallenger(subject);
        assertEq(challenges.length, 2);
    }

    function testTotalChallenges() public {
        uint256 sealId = _issueSeal();

        assertEq(challenge.totalChallenges(), 0);

        vm.prank(subject);
        challenge.createChallenge(sealId, "Test", CHALLENGE_EVIDENCE);

        assertEq(challenge.totalChallenges(), 1);
    }

    function testIsChallengeActive() public {
        uint256 sealId = _issueSeal();

        assertFalse(challenge.isChallengeActive(sealId, subject));

        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(sealId, "Test", CHALLENGE_EVIDENCE);

        assertTrue(challenge.isChallengeActive(sealId, subject));

        vm.prank(resolver);
        challenge.resolveChallenge(challengeId, ISealChallenge.ChallengeStatus.Rejected, "No");

        assertFalse(challenge.isChallengeActive(sealId, subject));
    }

    // ═══════════════════════════════════════════════════════════════
    //  ADMIN
    // ═══════════════════════════════════════════════════════════════

    function testSetChallengeWindow() public {
        challenge.setChallengeWindow(14 days);
        assertEq(challenge.challengeWindow(), 14 days);
    }

    function testCannotSetTooShortWindow() public {
        vm.expectRevert("SealChallenge: window too short");
        challenge.setChallengeWindow(12 hours);
    }

    function testCannotSetTooLongWindow() public {
        vm.expectRevert("SealChallenge: window too long");
        challenge.setChallengeWindow(91 days);
    }

    function testNonAdminCannotSetWindow() public {
        vm.prank(stranger);
        vm.expectRevert(); // AccessControl revert
        challenge.setChallengeWindow(14 days);
    }

    // ═══════════════════════════════════════════════════════════════
    //  EDGE CASES
    // ═══════════════════════════════════════════════════════════════

    function testGetNonExistentChallenge() public {
        vm.expectRevert("SealChallenge: not found");
        challenge.getChallenge(999);
    }

    function testChallengeWindowAppliedCorrectly() public {
        // Set 14 day window
        challenge.setChallengeWindow(14 days);

        uint256 sealId = _issueSeal();
        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(sealId, "Test", CHALLENGE_EVIDENCE);

        ISealChallenge.Challenge memory c = challenge.getChallenge(challengeId);
        assertEq(c.deadline, c.createdAt + 14 days);
    }

    function testSustainedChallengeRevokesViaRegistry() public {
        uint256 sealId = _issueSeal();

        // Verify seal is not revoked
        SealRegistry.Seal memory sealBefore = registry.getSeal(sealId);
        assertFalse(sealBefore.revoked);

        // Challenge and sustain
        vm.prank(subject);
        uint256 challengeId = challenge.createChallenge(sealId, "Bad seal", CHALLENGE_EVIDENCE);

        vm.prank(resolver);
        challenge.resolveChallenge(
            challengeId,
            ISealChallenge.ChallengeStatus.Sustained,
            "Evidence confirms unfair evaluation"
        );

        // Verify seal IS now revoked
        SealRegistry.Seal memory sealAfter = registry.getSeal(sealId);
        assertTrue(sealAfter.revoked);
    }
}
