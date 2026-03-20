// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SealRegistry.sol";
import "../src/SealAggregator.sol";
import "../src/mocks/MockIdentityRegistry.sol";

contract SealAggregatorTest is Test {
    SealRegistry registry1;
    SealRegistry registry2;
    SealAggregator aggregator;
    MockIdentityRegistry identityRegistry;

    address admin = address(this);
    address subject1 = makeAddr("subject1");
    address subject2 = makeAddr("subject2");
    address evaluator1 = makeAddr("evaluator1");
    address evaluator2 = makeAddr("evaluator2");

    bytes32 SKILLFUL = keccak256("SKILLFUL");
    bytes32 RELIABLE = keccak256("RELIABLE");

    function setUp() public {
        // Deploy identity registry and registries
        identityRegistry = new MockIdentityRegistry();
        registry1 = new SealRegistry(address(identityRegistry));
        registry2 = new SealRegistry(address(identityRegistry));

        // Register evaluators as agents in identity registry
        identityRegistry.addAgent(1, "eval1.com", evaluator1);
        identityRegistry.addAgent(2, "eval2.com", evaluator2);

        // Register seal domains for evaluators on both registries
        bytes32[] memory types = new bytes32[](2);
        types[0] = SKILLFUL;
        types[1] = RELIABLE;

        vm.prank(evaluator1);
        registry1.registerAgentSealDomains(types);
        vm.prank(evaluator2);
        registry1.registerAgentSealDomains(types);

        vm.prank(evaluator1);
        registry2.registerAgentSealDomains(types);
        vm.prank(evaluator2);
        registry2.registerAgentSealDomains(types);

        // Deploy aggregator
        aggregator = new SealAggregator();

        // Add registries
        aggregator.addRegistry(registry1, 100, "ExecutionMarket");
        aggregator.addRegistry(registry2, 80, "MoltX");
    }

    // ─── Helpers ────────────────────────────────────────────

    function _issueSeal(
        SealRegistry reg,
        address subject,
        address evaluator,
        bytes32 sealType,
        uint8 score
    ) internal returns (uint256) {
        vm.prank(evaluator);
        return reg.issueSealA2H(subject, sealType, score, bytes32(0), 0);
    }

    function _issueSealWithExpiry(
        SealRegistry reg,
        address subject,
        address evaluator,
        bytes32 sealType,
        uint8 score,
        uint48 expiresAt
    ) internal returns (uint256) {
        vm.prank(evaluator);
        return reg.issueSealA2H(subject, sealType, score, bytes32(0), expiresAt);
    }

    /// @dev Register a new evaluator (for tests that need many evaluators)
    function _registerEvaluator(
        uint256 agentId,
        address eval,
        SealRegistry reg
    ) internal {
        identityRegistry.addAgent(agentId, "eval.com", eval);
        bytes32[] memory types = new bytes32[](2);
        types[0] = SKILLFUL;
        types[1] = RELIABLE;
        vm.prank(eval);
        reg.registerAgentSealDomains(types);
    }

    function _registerEvaluatorBoth(uint256 agentId, address eval) internal {
        identityRegistry.addAgent(agentId, "eval.com", eval);
        bytes32[] memory types = new bytes32[](2);
        types[0] = SKILLFUL;
        types[1] = RELIABLE;
        vm.prank(eval);
        registry1.registerAgentSealDomains(types);
        vm.prank(eval);
        registry2.registerAgentSealDomains(types);
    }

    // ─── Admin Tests ────────────────────────────────────────

    function testAddRegistry() public view {
        assertEq(aggregator.totalRegistries(), 2);
    }

    function testAddRegistryEvent() public {
        SealRegistry newReg = new SealRegistry(address(identityRegistry));
        vm.expectEmit(true, true, false, true);
        emit SealAggregator.RegistryAdded(2, address(newReg), 50, "NewReg");
        aggregator.addRegistry(newReg, 50, "NewReg");
    }

    function testMaxRegistries() public {
        for (uint256 i = 0; i < 8; i++) {
            SealRegistry newReg = new SealRegistry(address(identityRegistry));
            aggregator.addRegistry(newReg, 100, "Extra");
        }
        assertEq(aggregator.totalRegistries(), 10);

        SealRegistry extraReg = new SealRegistry(address(identityRegistry));
        vm.expectRevert(SealAggregator.TooManyRegistries.selector);
        aggregator.addRegistry(extraReg, 100, "TooMany");
    }

    function testInvalidWeight() public {
        SealRegistry newReg = new SealRegistry(address(identityRegistry));
        vm.expectRevert(SealAggregator.InvalidWeight.selector);
        aggregator.addRegistry(newReg, 101, "Invalid");
    }

    function testUpdateRegistry() public {
        aggregator.updateRegistry(0, 50, false);
        (,uint8 weight,, bool active) = aggregator.registries(0);
        assertEq(weight, 50);
        assertFalse(active);
    }

    function testUpdateRegistryInvalidIndex() public {
        vm.expectRevert(SealAggregator.InvalidIndex.selector);
        aggregator.updateRegistry(99, 50, true);
    }

    function testUpdateRegistryInvalidWeight() public {
        vm.expectRevert(SealAggregator.InvalidWeight.selector);
        aggregator.updateRegistry(0, 150, true);
    }

    function testNotAdmin() public {
        vm.prank(subject1);
        vm.expectRevert(SealAggregator.NotAdmin.selector);
        aggregator.addRegistry(registry1, 100, "Fail");
    }

    function testTransferAdmin() public {
        aggregator.transferAdmin(subject1);
        assertEq(aggregator.admin(), subject1);

        vm.expectRevert(SealAggregator.NotAdmin.selector);
        aggregator.addRegistry(registry1, 100, "Fail");
    }

    function testSetTierThresholds() public {
        aggregator.setTierThresholds(2, 5, 15, 30);
        assertEq(aggregator.tierEmerging(), 2);
        assertEq(aggregator.tierTrusted(), 5);
        assertEq(aggregator.tierEstablished(), 15);
        assertEq(aggregator.tierElite(), 30);
    }

    function testInvalidThresholds() public {
        vm.expectRevert(SealAggregator.InvalidThresholds.selector);
        aggregator.setTierThresholds(10, 5, 15, 30);
    }

    // ─── Aggregation Tests ──────────────────────────────────

    function testEmptyProfile() public view {
        SealAggregator.AggregatedProfile memory profile = aggregator.getAggregatedProfile(subject1);
        assertEq(profile.subject, subject1);
        assertEq(profile.totalSeals, 0);
        assertEq(profile.activeSeals, 0);
        assertEq(profile.registriesPresent, 0);
        assertEq(uint(profile.tier), uint(SealAggregator.TrustTier.Newcomer));
    }

    function testSingleRegistryProfile() public {
        _issueSeal(registry1, subject1, evaluator1, SKILLFUL, 80);
        _issueSeal(registry1, subject1, evaluator2, RELIABLE, 90);

        SealAggregator.AggregatedProfile memory profile = aggregator.getAggregatedProfile(subject1);
        assertEq(profile.totalSeals, 2);
        assertEq(profile.activeSeals, 2);
        assertEq(profile.registriesPresent, 1);
        assertTrue(profile.weightedScore > 0);
    }

    function testMultiRegistryProfile() public {
        _issueSeal(registry1, subject1, evaluator1, SKILLFUL, 80);
        _issueSeal(registry2, subject1, evaluator2, RELIABLE, 90);

        SealAggregator.AggregatedProfile memory profile = aggregator.getAggregatedProfile(subject1);
        assertEq(profile.totalSeals, 2);
        assertEq(profile.activeSeals, 2);
        assertEq(profile.registriesPresent, 2);
    }

    function testWeightedScoring() public {
        _issueSeal(registry1, subject1, evaluator1, SKILLFUL, 80);
        _issueSeal(registry2, subject1, evaluator2, SKILLFUL, 60);

        SealAggregator.AggregatedProfile memory profile = aggregator.getAggregatedProfile(subject1);
        assertTrue(profile.weightedScore > 0);
    }

    function testRevokedSealsExcluded() public {
        uint256 sealId = _issueSeal(registry1, subject1, evaluator1, SKILLFUL, 80);
        _issueSeal(registry1, subject1, evaluator2, RELIABLE, 90);

        vm.prank(evaluator1);
        registry1.revokeSeal(sealId, "test revoke");

        SealAggregator.AggregatedProfile memory profile = aggregator.getAggregatedProfile(subject1);
        assertEq(profile.totalSeals, 2);
        assertEq(profile.activeSeals, 1);
    }

    function testExpiredSealsExcluded() public {
        _issueSealWithExpiry(registry1, subject1, evaluator1, SKILLFUL, 80, uint48(block.timestamp + 100));
        _issueSeal(registry1, subject1, evaluator2, RELIABLE, 90);

        vm.warp(block.timestamp + 200);

        SealAggregator.AggregatedProfile memory profile = aggregator.getAggregatedProfile(subject1);
        assertEq(profile.totalSeals, 2);
        assertEq(profile.activeSeals, 1);
    }

    function testInactiveRegistryExcluded() public {
        _issueSeal(registry1, subject1, evaluator1, SKILLFUL, 80);
        _issueSeal(registry2, subject1, evaluator2, RELIABLE, 90);

        aggregator.updateRegistry(1, 80, false);

        SealAggregator.AggregatedProfile memory profile = aggregator.getAggregatedProfile(subject1);
        assertEq(profile.registriesPresent, 1);
    }

    // ─── Category Score Tests ───────────────────────────────

    function testCategoryScore() public {
        _issueSeal(registry1, subject1, evaluator1, SKILLFUL, 80);
        _issueSeal(registry1, subject1, evaluator2, SKILLFUL, 90);
        _issueSeal(registry2, subject1, evaluator1, SKILLFUL, 70);

        SealAggregator.CategoryScore memory score = aggregator.getCategoryScore(subject1, SKILLFUL);
        assertEq(score.sealType, SKILLFUL);
        assertEq(score.totalSeals, 3);
        assertTrue(score.weightedScore > 0);
    }

    function testCategoryScoreEmpty() public view {
        SealAggregator.CategoryScore memory score = aggregator.getCategoryScore(subject1, SKILLFUL);
        assertEq(score.totalSeals, 0);
        assertEq(score.weightedScore, 0);
    }

    function testCategoryScoreFiltersType() public {
        _issueSeal(registry1, subject1, evaluator1, SKILLFUL, 80);
        _issueSeal(registry1, subject1, evaluator2, RELIABLE, 90);

        SealAggregator.CategoryScore memory skillScore = aggregator.getCategoryScore(subject1, SKILLFUL);
        assertEq(skillScore.totalSeals, 1);
    }

    // ─── Batch Tests ────────────────────────────────────────

    function testBatchAggregateProfiles() public {
        _issueSeal(registry1, subject1, evaluator1, SKILLFUL, 80);
        _issueSeal(registry1, subject2, evaluator1, RELIABLE, 70);

        address[] memory subjects = new address[](2);
        subjects[0] = subject1;
        subjects[1] = subject2;

        SealAggregator.AggregatedProfile[] memory profiles = aggregator.batchAggregateProfiles(subjects);
        assertEq(profiles.length, 2);
        assertEq(profiles[0].subject, subject1);
        assertEq(profiles[1].subject, subject2);
        assertEq(profiles[0].totalSeals, 1);
        assertEq(profiles[1].totalSeals, 1);
    }

    function testBatchEmpty() public view {
        address[] memory subjects = new address[](0);
        SealAggregator.AggregatedProfile[] memory profiles = aggregator.batchAggregateProfiles(subjects);
        assertEq(profiles.length, 0);
    }

    // ─── Comparison Tests ───────────────────────────────────

    function testCompareSubjects() public {
        _issueSeal(registry1, subject1, evaluator1, SKILLFUL, 90);
        _issueSeal(registry1, subject1, evaluator2, RELIABLE, 85);
        _issueSeal(registry1, subject2, evaluator1, SKILLFUL, 70);

        SealAggregator.ComparisonResult memory result = aggregator.compareSubjects(subject1, subject2);
        assertEq(result.subjectA, subject1);
        assertEq(result.subjectB, subject2);
        assertTrue(result.scoreA > result.scoreB);
        assertTrue(result.sealsA > result.sealsB);
    }

    function testCompareBothEmpty() public view {
        SealAggregator.ComparisonResult memory result = aggregator.compareSubjects(subject1, subject2);
        assertEq(result.scoreA, 0);
        assertEq(result.scoreB, 0);
    }

    // ─── Trust Tier Tests ───────────────────────────────────

    function testTierNewcomer() public view {
        SealAggregator.AggregatedProfile memory profile = aggregator.getAggregatedProfile(subject1);
        assertEq(uint(profile.tier), uint(SealAggregator.TrustTier.Newcomer));
    }

    function testTierEmerging() public {
        // Need 4+ evaluators for 4 seals
        for (uint256 i = 0; i < 4; i++) {
            address eval = address(uint160(0x3000 + i));
            _registerEvaluator(100 + i, eval, registry1);
            _issueSeal(registry1, subject1, eval, SKILLFUL, 70);
        }

        SealAggregator.AggregatedProfile memory profile = aggregator.getAggregatedProfile(subject1);
        assertTrue(uint(profile.tier) >= uint(SealAggregator.TrustTier.Emerging));
    }

    function testTierTrusted() public {
        for (uint256 i = 0; i < 12; i++) {
            address eval = address(uint160(0x3000 + i));
            _registerEvaluator(100 + i, eval, registry1);
            _issueSeal(registry1, subject1, eval, SKILLFUL, 80);
        }

        SealAggregator.AggregatedProfile memory profile = aggregator.getAggregatedProfile(subject1);
        assertTrue(uint(profile.tier) >= uint(SealAggregator.TrustTier.Trusted));
    }

    function testTierEstablished() public {
        for (uint256 i = 0; i < 15; i++) {
            address eval = address(uint160(0x3000 + i));
            _registerEvaluator(100 + i, eval, registry1);
            _issueSeal(registry1, subject1, eval, SKILLFUL, 80);
        }
        for (uint256 i = 0; i < 12; i++) {
            address eval = address(uint160(0x4000 + i));
            _registerEvaluatorBoth(200 + i, eval);
            _issueSeal(registry2, subject1, eval, RELIABLE, 85);
        }

        SealAggregator.AggregatedProfile memory profile = aggregator.getAggregatedProfile(subject1);
        assertTrue(uint(profile.tier) >= uint(SealAggregator.TrustTier.Established));
    }

    function testGetTrustTier() public view {
        SealAggregator.TrustTier tier = aggregator.getTrustTier(subject1);
        assertEq(uint(tier), uint(SealAggregator.TrustTier.Newcomer));
    }

    // ─── Multi-Registry Presence Tests ──────────────────────

    function testHasMultiRegistryPresence() public {
        _issueSeal(registry1, subject1, evaluator1, SKILLFUL, 80);
        _issueSeal(registry2, subject1, evaluator2, RELIABLE, 90);

        assertTrue(aggregator.hasMultiRegistryPresence(subject1, 2));
        assertFalse(aggregator.hasMultiRegistryPresence(subject1, 3));
    }

    function testHasMultiRegistryPresenceNone() public view {
        assertFalse(aggregator.hasMultiRegistryPresence(subject1, 1));
    }

    function testHasMultiRegistryPresenceSingle() public {
        _issueSeal(registry1, subject1, evaluator1, SKILLFUL, 80);

        assertTrue(aggregator.hasMultiRegistryPresence(subject1, 1));
        assertFalse(aggregator.hasMultiRegistryPresence(subject1, 2));
    }

    // ─── Active Registry Count ──────────────────────────────

    function testActiveRegistryCount() public view {
        assertEq(aggregator.activeRegistryCount(), 2);
    }

    function testActiveRegistryCountAfterDeactivation() public {
        aggregator.updateRegistry(1, 80, false);
        assertEq(aggregator.activeRegistryCount(), 1);
    }

    // ─── Custom Tier Thresholds ─────────────────────────────

    function testCustomTierThresholds() public {
        aggregator.setTierThresholds(1, 3, 8, 15);

        _issueSeal(registry1, subject1, evaluator1, SKILLFUL, 80);
        _issueSeal(registry1, subject1, evaluator2, RELIABLE, 90);

        SealAggregator.AggregatedProfile memory profile = aggregator.getAggregatedProfile(subject1);
        assertTrue(uint(profile.tier) >= uint(SealAggregator.TrustTier.Emerging));
    }
}
