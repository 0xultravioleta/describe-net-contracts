// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SealRegistry.sol";
import "../src/SealQuery.sol";
import "../src/mocks/MockIdentityRegistry.sol";

contract SealQueryTest is Test {
    SealRegistry public sealRegistry;
    SealQuery public sealQuery;
    MockIdentityRegistry public identityRegistry;

    address public owner = makeAddr("owner");
    address public human1 = makeAddr("human1");
    address public human2 = makeAddr("human2");
    address public human3 = makeAddr("human3");
    address public agent1 = makeAddr("agent1");
    address public agent2 = makeAddr("agent2");
    address public agent3 = makeAddr("agent3");

    uint256 constant AGENT1_ID = 1;
    uint256 constant AGENT2_ID = 2;
    uint256 constant AGENT3_ID = 3;

    bytes32 constant SKILLFUL = keccak256("SKILLFUL");
    bytes32 constant RELIABLE = keccak256("RELIABLE");
    bytes32 constant FAIR = keccak256("FAIR");
    bytes32 constant CREATIVE = keccak256("CREATIVE");
    bytes32 constant THOROUGH = keccak256("THOROUGH");
    bytes32 constant HELPFUL = keccak256("HELPFUL");
    bytes32 constant ACCURATE = keccak256("ACCURATE");
    bytes32 constant RESPONSIVE = keccak256("RESPONSIVE");
    bytes32 constant ETHICAL = keccak256("ETHICAL");
    bytes32 constant PROFESSIONAL = keccak256("PROFESSIONAL");
    bytes32 constant FRIENDLY = keccak256("FRIENDLY");
    bytes32 constant ENGAGED = keccak256("ENGAGED");
    bytes32 constant CURIOUS = keccak256("CURIOUS");

    bytes32 constant EVIDENCE = keccak256("evidence");

    function setUp() public {
        vm.startPrank(owner);
        identityRegistry = new MockIdentityRegistry();
        sealRegistry = new SealRegistry(address(identityRegistry));

        // Register 3 agents
        identityRegistry.addAgent(AGENT1_ID, "agent1.describe.net", agent1);
        identityRegistry.addAgent(AGENT2_ID, "agent2.describe.net", agent2);
        identityRegistry.addAgent(AGENT3_ID, "agent3.describe.net", agent3);
        vm.stopPrank();

        // Deploy query contract
        sealQuery = new SealQuery(address(sealRegistry));

        // Register agent seal domains
        _registerAgentDomains(agent1);
        _registerAgentDomains(agent2);
        _registerAgentDomains(agent3);
    }

    function _registerAgentDomains(address agent) internal {
        vm.startPrank(agent);
        bytes32[] memory types = new bytes32[](6);
        types[0] = SKILLFUL;
        types[1] = RELIABLE;
        types[2] = THOROUGH;
        types[3] = HELPFUL;
        types[4] = FAIR;
        types[5] = ACCURATE;
        sealRegistry.registerAgentSealDomains(types);
        vm.stopPrank();
    }

    // ============================================================
    //                  REPUTATION PROFILE TESTS
    // ============================================================

    function testGetReputationProfile_Empty() public view {
        SealQuery.ReputationProfile memory profile = sealQuery.getReputationProfile(human1);
        assertEq(profile.subject, human1);
        assertEq(profile.totalSeals, 0);
        assertEq(profile.activeSeals, 0);
        assertEq(profile.revokedSeals, 0);
        assertEq(profile.expiredSeals, 0);
        assertEq(profile.averageScore, 0);
        assertEq(profile.uniqueEvaluators, 0);
    }

    function testGetReputationProfile_SingleSeal() public {
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 85, EVIDENCE, 0);

        SealQuery.ReputationProfile memory profile = sealQuery.getReputationProfile(human1);
        assertEq(profile.totalSeals, 1);
        assertEq(profile.activeSeals, 1);
        assertEq(profile.averageScore, 85);
        assertEq(profile.uniqueEvaluators, 1);
        assertEq(profile.quadrantCounts[2], 1); // A2H = index 2
        assertEq(profile.quadrantAvgScores[2], 85);
    }

    function testGetReputationProfile_MultipleEvaluators() public {
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, 0);

        vm.prank(agent2);
        sealRegistry.issueSealA2H(human1, RELIABLE, 90, EVIDENCE, 0);

        vm.prank(agent3);
        sealRegistry.issueSealA2H(human1, THOROUGH, 70, EVIDENCE, 0);

        SealQuery.ReputationProfile memory profile = sealQuery.getReputationProfile(human1);
        assertEq(profile.totalSeals, 3);
        assertEq(profile.activeSeals, 3);
        assertEq(profile.averageScore, 80); // (80+90+70)/3 = 80
        assertEq(profile.uniqueEvaluators, 3);
    }

    function testGetReputationProfile_WithRevoked() public {
        vm.prank(agent1);
        uint256 sealId = sealRegistry.issueSealA2H(human1, SKILLFUL, 50, EVIDENCE, 0);

        vm.prank(agent2);
        sealRegistry.issueSealA2H(human1, RELIABLE, 90, EVIDENCE, 0);

        // Revoke first seal
        vm.prank(agent1);
        sealRegistry.revokeSeal(sealId, "testing");

        SealQuery.ReputationProfile memory profile = sealQuery.getReputationProfile(human1);
        assertEq(profile.totalSeals, 2);
        assertEq(profile.activeSeals, 1);
        assertEq(profile.revokedSeals, 1);
        assertEq(profile.averageScore, 90); // Only the non-revoked seal counts
    }

    function testGetReputationProfile_WithExpired() public {
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 60, EVIDENCE, uint48(block.timestamp + 100));

        vm.prank(agent2);
        sealRegistry.issueSealA2H(human1, RELIABLE, 80, EVIDENCE, 0); // never expires

        // Fast forward past expiry
        vm.warp(block.timestamp + 200);

        SealQuery.ReputationProfile memory profile = sealQuery.getReputationProfile(human1);
        assertEq(profile.totalSeals, 2);
        assertEq(profile.activeSeals, 1);
        assertEq(profile.expiredSeals, 1);
        assertEq(profile.averageScore, 80);
    }

    function testGetReputationProfile_MultipleQuadrants() public {
        // A2H seal
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, 0);

        // H2H seal
        vm.prank(human2);
        sealRegistry.issueSealH2H(human1, CREATIVE, 70, EVIDENCE);

        SealQuery.ReputationProfile memory profile = sealQuery.getReputationProfile(human1);
        assertEq(profile.totalSeals, 2);
        assertEq(profile.activeSeals, 2);
        assertEq(profile.quadrantCounts[0], 1); // H2H
        assertEq(profile.quadrantCounts[2], 1); // A2H
        assertEq(profile.quadrantAvgScores[0], 70);
        assertEq(profile.quadrantAvgScores[2], 80);
    }

    function testGetReputationProfile_DuplicateEvaluator() public {
        vm.startPrank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human1, RELIABLE, 90, EVIDENCE, 0);
        vm.stopPrank();

        SealQuery.ReputationProfile memory profile = sealQuery.getReputationProfile(human1);
        assertEq(profile.totalSeals, 2);
        assertEq(profile.activeSeals, 2);
        assertEq(profile.uniqueEvaluators, 1); // Same evaluator, counted once
    }

    function testGetReputationProfile_MostRecentTimestamp() public {
        vm.warp(1000);
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, 0);

        vm.warp(2000);
        vm.prank(agent2);
        sealRegistry.issueSealA2H(human1, RELIABLE, 90, EVIDENCE, 0);

        SealQuery.ReputationProfile memory profile = sealQuery.getReputationProfile(human1);
        assertEq(profile.mostRecentSealTimestamp, 2000);
    }

    // ============================================================
    //                  BATCH PROFILES TESTS
    // ============================================================

    function testBatchGetProfiles_Empty() public view {
        address[] memory subjects = new address[](2);
        subjects[0] = human1;
        subjects[1] = human2;

        SealQuery.ReputationProfile[] memory profiles = sealQuery.batchGetProfiles(subjects);
        assertEq(profiles.length, 2);
        assertEq(profiles[0].totalSeals, 0);
        assertEq(profiles[1].totalSeals, 0);
    }

    function testBatchGetProfiles_Mixed() public {
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 90, EVIDENCE, 0);

        // human2 has nothing

        vm.prank(agent2);
        sealRegistry.issueSealA2H(human3, RELIABLE, 70, EVIDENCE, 0);

        address[] memory subjects = new address[](3);
        subjects[0] = human1;
        subjects[1] = human2;
        subjects[2] = human3;

        SealQuery.ReputationProfile[] memory profiles = sealQuery.batchGetProfiles(subjects);
        assertEq(profiles.length, 3);
        assertEq(profiles[0].activeSeals, 1);
        assertEq(profiles[0].averageScore, 90);
        assertEq(profiles[1].activeSeals, 0);
        assertEq(profiles[2].activeSeals, 1);
        assertEq(profiles[2].averageScore, 70);
    }

    function testBatchGetProfiles_TooMany() public {
        address[] memory subjects = new address[](51);
        for (uint256 i = 0; i < 51; i++) {
            subjects[i] = makeAddr(string(abi.encodePacked("subject", i)));
        }
        vm.expectRevert("Max 50 subjects per batch");
        sealQuery.batchGetProfiles(subjects);
    }

    // ============================================================
    //                  EVALUATOR PROFILE TESTS
    // ============================================================

    function testGetEvaluatorProfile_Empty() public view {
        SealQuery.EvaluatorProfile memory profile = sealQuery.getEvaluatorProfile(agent1);
        assertEq(profile.evaluator, agent1);
        assertEq(profile.totalIssued, 0);
    }

    function testGetEvaluatorProfile_WithSeals() public {
        vm.startPrank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human2, RELIABLE, 90, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human3, THOROUGH, 70, EVIDENCE, 0);
        vm.stopPrank();

        SealQuery.EvaluatorProfile memory profile = sealQuery.getEvaluatorProfile(agent1);
        assertEq(profile.totalIssued, 3);
        assertEq(profile.revokedCount, 0);
        assertEq(profile.averageScoreGiven, 80); // (80+90+70)/3
        assertEq(profile.uniqueSubjects, 3);
        assertEq(profile.quadrantCounts[2], 3); // All A2H
    }

    function testGetEvaluatorProfile_WithRevocations() public {
        vm.startPrank(agent1);
        uint256 id1 = sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human2, RELIABLE, 90, EVIDENCE, 0);
        sealRegistry.revokeSeal(id1, "mistake");
        vm.stopPrank();

        SealQuery.EvaluatorProfile memory profile = sealQuery.getEvaluatorProfile(agent1);
        assertEq(profile.totalIssued, 2);
        assertEq(profile.revokedCount, 1);
        assertEq(profile.averageScoreGiven, 90); // Only non-revoked
        assertEq(profile.uniqueSubjects, 1); // Only human2 counted (human1's seal was revoked)
    }

    function testGetEvaluatorProfile_ScoreVariance() public {
        // All same score = zero variance
        vm.startPrank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human2, RELIABLE, 80, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human3, THOROUGH, 80, EVIDENCE, 0);
        vm.stopPrank();

        SealQuery.EvaluatorProfile memory profile = sealQuery.getEvaluatorProfile(agent1);
        assertEq(profile.scoreVariance, 0); // Zero variance for identical scores
    }

    function testGetEvaluatorProfile_DuplicateSubject() public {
        vm.startPrank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human1, RELIABLE, 90, EVIDENCE, 0); // Same subject
        vm.stopPrank();

        SealQuery.EvaluatorProfile memory profile = sealQuery.getEvaluatorProfile(agent1);
        assertEq(profile.uniqueSubjects, 1); // human1 counted once
    }

    // ============================================================
    //                  COMPARE REPUTATION TESTS
    // ============================================================

    function testCompareReputation_Ranked() public {
        // Give different scores to different humans
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 60, EVIDENCE, 0);

        vm.prank(agent1);
        sealRegistry.issueSealA2H(human2, SKILLFUL, 90, EVIDENCE, 0);

        vm.prank(agent1);
        sealRegistry.issueSealA2H(human3, SKILLFUL, 75, EVIDENCE, 0);

        address[] memory subjects = new address[](3);
        subjects[0] = human1;
        subjects[1] = human2;
        subjects[2] = human3;

        SealQuery.ComparisonResult[] memory results = sealQuery.compareReputation(subjects, false, SealRegistry.Quadrant.H2H);

        // Should be sorted descending by score
        assertEq(results[0].subject, human2); // 90
        assertEq(results[0].rank, 1);
        assertEq(results[1].subject, human3); // 75
        assertEq(results[1].rank, 2);
        assertEq(results[2].subject, human1); // 60
        assertEq(results[2].rank, 3);
    }

    function testCompareReputation_WithQuadrantFilter() public {
        // Give A2H seal to human1
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 90, EVIDENCE, 0);

        // Give H2H seal to human2
        vm.prank(human3);
        sealRegistry.issueSealH2H(human2, CREATIVE, 80, EVIDENCE);

        address[] memory subjects = new address[](2);
        subjects[0] = human1;
        subjects[1] = human2;

        // Filter by A2H — only human1 should have score
        SealQuery.ComparisonResult[] memory results = sealQuery.compareReputation(subjects, true, SealRegistry.Quadrant.A2H);
        assertEq(results[0].subject, human1);
        assertEq(results[0].overallScore, 90);
        assertEq(results[0].activeCount, 1);
        assertEq(results[1].overallScore, 0); // human2 has no A2H seals
    }

    function testCompareReputation_EmptySubjects() public view {
        address[] memory subjects = new address[](2);
        subjects[0] = human1;
        subjects[1] = human2;

        SealQuery.ComparisonResult[] memory results = sealQuery.compareReputation(subjects, false, SealRegistry.Quadrant.H2H);
        assertEq(results[0].overallScore, 0);
        assertEq(results[1].overallScore, 0);
    }

    function testCompareReputation_TooMany() public {
        address[] memory subjects = new address[](51);
        for (uint256 i = 0; i < 51; i++) {
            subjects[i] = makeAddr(string(abi.encodePacked("sub", i)));
        }
        vm.expectRevert("Max 50 subjects");
        sealQuery.compareReputation(subjects, false, SealRegistry.Quadrant.H2H);
    }

    // ============================================================
    //                  SEAL SUMMARIES TESTS
    // ============================================================

    function testGetSealSummaries_Basic() public {
        vm.startPrank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 85, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human1, RELIABLE, 90, EVIDENCE, 0);
        vm.stopPrank();

        SealQuery.SealSummary[] memory summaries = sealQuery.getSealSummaries(human1, 0, 10);
        assertEq(summaries.length, 2);
        assertEq(summaries[0].score, 85);
        assertEq(summaries[0].quadrant, uint8(SealRegistry.Quadrant.A2H));
        assertTrue(summaries[0].active);
        assertEq(summaries[1].score, 90);
    }

    function testGetSealSummaries_Pagination() public {
        vm.startPrank(agent1);
        for (uint256 i = 0; i < 5; i++) {
            sealRegistry.issueSealA2H(human1, SKILLFUL, uint8(60 + i * 10), EVIDENCE, 0);
        }
        vm.stopPrank();

        // Page 1: first 2
        SealQuery.SealSummary[] memory page1 = sealQuery.getSealSummaries(human1, 0, 2);
        assertEq(page1.length, 2);
        assertEq(page1[0].score, 60);
        assertEq(page1[1].score, 70);

        // Page 2: next 2
        SealQuery.SealSummary[] memory page2 = sealQuery.getSealSummaries(human1, 2, 2);
        assertEq(page2.length, 2);
        assertEq(page2[0].score, 80);
        assertEq(page2[1].score, 90);

        // Page 3: last 1
        SealQuery.SealSummary[] memory page3 = sealQuery.getSealSummaries(human1, 4, 2);
        assertEq(page3.length, 1);
        assertEq(page3[0].score, 100);
    }

    function testGetSealSummaries_OffsetBeyondEnd() public {
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, 0);

        SealQuery.SealSummary[] memory summaries = sealQuery.getSealSummaries(human1, 5, 10);
        assertEq(summaries.length, 0);
    }

    function testGetSealSummaries_ActiveFlag() public {
        vm.prank(agent1);
        uint256 id1 = sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, uint48(block.timestamp + 100));

        vm.prank(agent2);
        sealRegistry.issueSealA2H(human1, RELIABLE, 90, EVIDENCE, 0);

        // Expire the first seal
        vm.warp(block.timestamp + 200);

        SealQuery.SealSummary[] memory summaries = sealQuery.getSealSummaries(human1, 0, 10);
        assertFalse(summaries[0].active); // expired
        assertTrue(summaries[1].active); // never expires
    }

    function testGetSealSummaries_RevokedNotActive() public {
        vm.startPrank(agent1);
        uint256 id1 = sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, 0);
        sealRegistry.revokeSeal(id1, "test");
        vm.stopPrank();

        SealQuery.SealSummary[] memory summaries = sealQuery.getSealSummaries(human1, 0, 10);
        assertFalse(summaries[0].active);
    }

    // ============================================================
    //                  TRUST GRAPH TESTS
    // ============================================================

    function testGetTrustGraph_Empty() public view {
        address[] memory addrs = new address[](2);
        addrs[0] = human1;
        addrs[1] = human2;

        SealQuery.TrustEdge[] memory edges = sealQuery.getTrustGraph(addrs);
        assertEq(edges.length, 0);
    }

    function testGetTrustGraph_SingleEdge() public {
        vm.prank(human1);
        sealRegistry.issueSealH2H(human2, CREATIVE, 85, EVIDENCE);

        address[] memory addrs = new address[](2);
        addrs[0] = human1;
        addrs[1] = human2;

        SealQuery.TrustEdge[] memory edges = sealQuery.getTrustGraph(addrs);
        assertEq(edges.length, 1);
        assertEq(edges[0].evaluator, human1);
        assertEq(edges[0].subject, human2);
        assertEq(edges[0].sealCount, 1);
        assertEq(edges[0].averageScore, 85);
    }

    function testGetTrustGraph_BidirectionalEdges() public {
        vm.prank(human1);
        sealRegistry.issueSealH2H(human2, CREATIVE, 80, EVIDENCE);

        vm.prank(human2);
        sealRegistry.issueSealH2H(human1, PROFESSIONAL, 90, EVIDENCE);

        address[] memory addrs = new address[](2);
        addrs[0] = human1;
        addrs[1] = human2;

        SealQuery.TrustEdge[] memory edges = sealQuery.getTrustGraph(addrs);
        assertEq(edges.length, 2); // Bidirectional

        // Find edge human1→human2
        bool found12 = false;
        bool found21 = false;
        for (uint256 i = 0; i < edges.length; i++) {
            if (edges[i].evaluator == human1 && edges[i].subject == human2) {
                assertEq(edges[i].averageScore, 80);
                found12 = true;
            }
            if (edges[i].evaluator == human2 && edges[i].subject == human1) {
                assertEq(edges[i].averageScore, 90);
                found21 = true;
            }
        }
        assertTrue(found12);
        assertTrue(found21);
    }

    function testGetTrustGraph_MultipleSealsPerEdge() public {
        vm.warp(1000);
        vm.prank(human1);
        sealRegistry.issueSealH2H(human2, CREATIVE, 70, EVIDENCE);

        vm.warp(2000);
        vm.prank(human1);
        sealRegistry.issueSealH2H(human2, PROFESSIONAL, 90, EVIDENCE);

        address[] memory addrs = new address[](2);
        addrs[0] = human1;
        addrs[1] = human2;

        SealQuery.TrustEdge[] memory edges = sealQuery.getTrustGraph(addrs);
        assertEq(edges.length, 1);
        assertEq(edges[0].sealCount, 2);
        assertEq(edges[0].averageScore, 80); // (70+90)/2
        assertEq(edges[0].firstSeal, 1000);
        assertEq(edges[0].lastSeal, 2000);
    }

    function testGetTrustGraph_RevokedExcluded() public {
        vm.startPrank(human1);
        uint256 id1 = sealRegistry.issueSealH2H(human2, CREATIVE, 80, EVIDENCE);
        sealRegistry.revokeSeal(id1, "test");
        vm.stopPrank();

        address[] memory addrs = new address[](2);
        addrs[0] = human1;
        addrs[1] = human2;

        SealQuery.TrustEdge[] memory edges = sealQuery.getTrustGraph(addrs);
        assertEq(edges.length, 0); // Revoked seals excluded
    }

    function testGetTrustGraph_ThreeWay() public {
        vm.prank(human1);
        sealRegistry.issueSealH2H(human2, CREATIVE, 80, EVIDENCE);

        vm.prank(human2);
        sealRegistry.issueSealH2H(human3, PROFESSIONAL, 75, EVIDENCE);

        vm.prank(human3);
        sealRegistry.issueSealH2H(human1, FRIENDLY, 90, EVIDENCE);

        address[] memory addrs = new address[](3);
        addrs[0] = human1;
        addrs[1] = human2;
        addrs[2] = human3;

        SealQuery.TrustEdge[] memory edges = sealQuery.getTrustGraph(addrs);
        assertEq(edges.length, 3); // Triangle
    }

    function testGetTrustGraph_TooMany() public {
        address[] memory addrs = new address[](21);
        for (uint256 i = 0; i < 21; i++) {
            addrs[i] = makeAddr(string(abi.encodePacked("addr", i)));
        }
        vm.expectRevert("Max 20 addresses for trust graph");
        sealQuery.getTrustGraph(addrs);
    }

    // ============================================================
    //                  REPUTATION BY TYPES TESTS
    // ============================================================

    function testGetReputationByTypes_Basic() public {
        vm.startPrank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 90, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human1, RELIABLE, 70, EVIDENCE, 0);
        vm.stopPrank();

        bytes32[] memory types = new bytes32[](3);
        types[0] = SKILLFUL;
        types[1] = RELIABLE;
        types[2] = THOROUGH;

        (uint256[] memory scores, uint256[] memory counts) = sealQuery.getReputationByTypes(human1, types);
        assertEq(scores[0], 85); // SKILLFUL avg: (80+90)/2
        assertEq(counts[0], 2);
        assertEq(scores[1], 70); // RELIABLE
        assertEq(counts[1], 1);
        assertEq(scores[2], 0); // THOROUGH: no seals
        assertEq(counts[2], 0);
    }

    function testGetReputationByTypes_Empty() public view {
        bytes32[] memory types = new bytes32[](2);
        types[0] = SKILLFUL;
        types[1] = RELIABLE;

        (uint256[] memory scores, uint256[] memory counts) = sealQuery.getReputationByTypes(human1, types);
        assertEq(scores[0], 0);
        assertEq(counts[0], 0);
        assertEq(scores[1], 0);
        assertEq(counts[1], 0);
    }

    function testGetReputationByTypes_TooMany() public {
        bytes32[] memory types = new bytes32[](14);
        for (uint256 i = 0; i < 14; i++) {
            types[i] = keccak256(abi.encodePacked("type", i));
        }
        vm.expectRevert("Max 13 seal types");
        sealQuery.getReputationByTypes(human1, types);
    }

    // ============================================================
    //                  SEALS SINCE TESTS
    // ============================================================

    function testSealsSince_Basic() public {
        vm.warp(1000);
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, 0); // positive

        vm.warp(2000);
        vm.prank(agent2);
        sealRegistry.issueSealA2H(human1, RELIABLE, 30, EVIDENCE, 0); // negative

        vm.warp(3000);
        vm.prank(agent3);
        sealRegistry.issueSealA2H(human1, THOROUGH, 90, EVIDENCE, 0); // positive

        // Count seals since timestamp 1500
        (uint256 total, uint256 positive, uint256 negative) = sealQuery.sealsSince(human1, 1500);
        assertEq(total, 2);
        assertEq(positive, 1); // score 90
        assertEq(negative, 1); // score 30
    }

    function testSealsSince_AllBefore() public {
        vm.warp(1000);
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, 0);

        (uint256 total, uint256 positive, uint256 negative) = sealQuery.sealsSince(human1, 2000);
        assertEq(total, 0);
        assertEq(positive, 0);
        assertEq(negative, 0);
    }

    function testSealsSince_ExcludesRevoked() public {
        vm.warp(1000);
        vm.startPrank(agent1);
        uint256 id1 = sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, 0);
        sealRegistry.revokeSeal(id1, "test");
        vm.stopPrank();

        (uint256 total,,) = sealQuery.sealsSince(human1, 500);
        assertEq(total, 0); // Revoked excluded
    }

    function testSealsSince_BoundaryScore50() public {
        vm.warp(1000);
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 50, EVIDENCE, 0); // exactly 50 = positive

        (uint256 total, uint256 positive, uint256 negative) = sealQuery.sealsSince(human1, 500);
        assertEq(total, 1);
        assertEq(positive, 1); // score 50 counts as positive
        assertEq(negative, 0);
    }

    // ============================================================
    //              MEETS REPUTATION THRESHOLD TESTS
    // ============================================================

    function testMeetsReputationThreshold_Pass() public {
        vm.startPrank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 90, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 70, EVIDENCE, 0);
        vm.stopPrank();

        (bool meets, uint256 count, uint256 avg) = sealQuery.meetsReputationThreshold(human1, SKILLFUL, 3, 70);
        assertTrue(meets);
        assertEq(count, 3);
        assertEq(avg, 80); // (80+90+70)/3
    }

    function testMeetsReputationThreshold_FailCount() public {
        vm.startPrank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 90, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 85, EVIDENCE, 0);
        vm.stopPrank();

        (bool meets, uint256 count, uint256 avg) = sealQuery.meetsReputationThreshold(human1, SKILLFUL, 3, 70);
        assertFalse(meets); // Only 2, need 3
        assertEq(count, 2);
    }

    function testMeetsReputationThreshold_FailScore() public {
        vm.startPrank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 50, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 60, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 40, EVIDENCE, 0);
        vm.stopPrank();

        (bool meets, uint256 count, uint256 avg) = sealQuery.meetsReputationThreshold(human1, SKILLFUL, 3, 70);
        assertFalse(meets); // avg=50, need 70
        assertEq(avg, 50);
    }

    function testMeetsReputationThreshold_NoSeals() public view {
        (bool meets, uint256 count, uint256 avg) = sealQuery.meetsReputationThreshold(human1, SKILLFUL, 1, 50);
        assertFalse(meets);
        assertEq(count, 0);
        assertEq(avg, 0);
    }

    function testMeetsReputationThreshold_ZeroThresholds() public {
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 10, EVIDENCE, 0);

        (bool meets,,) = sealQuery.meetsReputationThreshold(human1, SKILLFUL, 0, 0);
        assertTrue(meets); // Zero thresholds always pass
    }

    // ============================================================
    //                  INTEGRATION TESTS
    // ============================================================

    function testFullWorkflow_AgentEcosystem() public {
        // Simulate a small agent ecosystem:
        // - 3 agents evaluate 3 humans
        // - Compare their reputations
        // - Build trust graph
        // - Check thresholds

        // Agent1 evaluates all 3 humans
        vm.startPrank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 95, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human2, SKILLFUL, 70, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human3, SKILLFUL, 85, EVIDENCE, 0);
        vm.stopPrank();

        // Agent2 evaluates 2 humans
        vm.startPrank(agent2);
        sealRegistry.issueSealA2H(human1, RELIABLE, 90, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human3, RELIABLE, 60, EVIDENCE, 0);
        vm.stopPrank();

        // Humans evaluate each other
        vm.prank(human1);
        sealRegistry.issueSealH2H(human2, CREATIVE, 80, EVIDENCE);

        vm.prank(human2);
        sealRegistry.issueSealH2H(human3, PROFESSIONAL, 75, EVIDENCE);

        // Compare all 3
        address[] memory subjects = new address[](3);
        subjects[0] = human1;
        subjects[1] = human2;
        subjects[2] = human3;

        SealQuery.ComparisonResult[] memory ranking = sealQuery.compareReputation(subjects, false, SealRegistry.Quadrant.H2H);
        assertEq(ranking[0].rank, 1);
        // human1 should be first (avg 92.5), then human3 (avg 72.5), then human2 (avg 75)
        assertEq(ranking[0].subject, human1); // (95+90)/2 = 92

        // Check threshold: human1 needs ≥1 SKILLFUL seal with avg ≥90
        (bool meets,,) = sealQuery.meetsReputationThreshold(human1, SKILLFUL, 1, 90);
        assertTrue(meets);

        // human2 doesn't meet the same threshold
        (bool meets2,,) = sealQuery.meetsReputationThreshold(human2, SKILLFUL, 1, 90);
        assertFalse(meets2);
    }

    function testFullWorkflow_EvaluatorCredibility() public {
        // Agent1 issues many seals with consistent scores
        vm.startPrank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human2, RELIABLE, 82, EVIDENCE, 0);
        sealRegistry.issueSealA2H(human3, THOROUGH, 78, EVIDENCE, 0);
        vm.stopPrank();

        SealQuery.EvaluatorProfile memory evalProfile = sealQuery.getEvaluatorProfile(agent1);
        assertEq(evalProfile.totalIssued, 3);
        assertEq(evalProfile.uniqueSubjects, 3);
        assertEq(evalProfile.averageScoreGiven, 80);
        // Low variance indicates consistent evaluator
    }

    function testFullWorkflow_TimeBased() public {
        // Issue seals over time and check sealsSince
        vm.warp(1000);
        vm.prank(agent1);
        sealRegistry.issueSealA2H(human1, SKILLFUL, 80, EVIDENCE, 0);

        vm.warp(2000);
        vm.prank(agent2);
        sealRegistry.issueSealA2H(human1, RELIABLE, 90, EVIDENCE, 0);

        vm.warp(3000);
        vm.prank(agent3);
        sealRegistry.issueSealA2H(human1, THOROUGH, 30, EVIDENCE, 0);

        // Check velocity since 1500
        (uint256 total, uint256 pos, uint256 neg) = sealQuery.sealsSince(human1, 1500);
        assertEq(total, 2);
        assertEq(pos, 1);
        assertEq(neg, 1);

        // Check full profile
        SealQuery.ReputationProfile memory profile = sealQuery.getReputationProfile(human1);
        assertEq(profile.activeSeals, 3);
        assertEq(profile.mostRecentSealTimestamp, 3000);
    }
}
