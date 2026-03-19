// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SealRegistry.sol";

/**
 * @title SealQuery
 * @author describe-net
 * @dev Advanced batch query and analytics layer for the SealRegistry
 *
 * Provides gas-efficient read-only operations for:
 * 1. Multi-subject reputation comparison
 * 2. Cross-quadrant analysis (who evaluates whom?)
 * 3. Evaluator credibility scoring
 * 4. Reputation deltas (change over time windows)
 * 5. Category-based leaderboards
 * 6. Trust graphs (evaluator-subject relationships)
 *
 * All functions are view/pure — no state modifications.
 * Designed to be called off-chain by reputation dashboards, agent matchers,
 * and swarm coordinators that need batch reputation data in a single RPC call.
 */
contract SealQuery {
    SealRegistry public immutable registry;

    /// @dev Reputation profile for a single subject
    struct ReputationProfile {
        address subject;
        uint256 totalSeals;
        uint256 activeSeals;
        uint256 revokedSeals;
        uint256 expiredSeals;
        uint256 averageScore;
        uint256[4] quadrantCounts; // [H2H, H2A, A2H, A2A]
        uint256[4] quadrantAvgScores;
        uint256 uniqueEvaluators;
        uint256 mostRecentSealTimestamp;
    }

    /// @dev Compact seal summary for batch reads
    struct SealSummary {
        uint256 sealId;
        bytes32 sealType;
        address evaluator;
        uint8 quadrant;
        uint8 score;
        uint48 issuedAt;
        bool active; // not revoked and not expired
    }

    /// @dev Evaluator credibility metrics
    struct EvaluatorProfile {
        address evaluator;
        uint256 totalIssued;
        uint256 revokedCount;
        uint256 averageScoreGiven;
        uint256 uniqueSubjects;
        uint256[4] quadrantCounts;
        uint256 scoreVariance; // scaled by 100
    }

    /// @dev Reputation comparison result
    struct ComparisonResult {
        address subject;
        uint256 overallScore;
        uint256 activeCount;
        uint256 rank; // 1-based, within the compared set
    }

    /// @dev Trust edge between evaluator and subject
    struct TrustEdge {
        address evaluator;
        address subject;
        uint256 sealCount;
        uint256 averageScore;
        uint48 firstSeal;
        uint48 lastSeal;
    }

    constructor(address _registry) {
        registry = SealRegistry(_registry);
    }

    /**
     * @notice Get full reputation profile for a subject
     * @dev Aggregates all seals into a comprehensive profile. Gas cost scales
     *      linearly with the number of seals the subject has received.
     * @param subject Address to profile
     * @return profile Complete reputation profile
     */
    function getReputationProfile(address subject) external view returns (ReputationProfile memory profile) {
        profile.subject = subject;
        uint256[] memory sealIds = registry.getSubjectSeals(subject);
        profile.totalSeals = sealIds.length;

        // Track unique evaluators with a simple array (gas-efficient for typical counts)
        address[] memory evaluators = new address[](sealIds.length);
        uint256 evalCount = 0;
        uint256 scoreSum = 0;
        uint256[4] memory qScoreSums;

        for (uint256 i = 0; i < sealIds.length; i++) {
            SealRegistry.Seal memory seal = registry.getSeal(sealIds[i]);

            if (seal.revoked) {
                profile.revokedSeals++;
                continue;
            }
            if (seal.expiresAt != 0 && block.timestamp > seal.expiresAt) {
                profile.expiredSeals++;
                continue;
            }

            profile.activeSeals++;
            scoreSum += seal.score;

            uint8 q = uint8(seal.quadrant);
            profile.quadrantCounts[q]++;
            qScoreSums[q] += seal.score;

            // Track most recent
            if (seal.issuedAt > profile.mostRecentSealTimestamp) {
                profile.mostRecentSealTimestamp = seal.issuedAt;
            }

            // Count unique evaluators (simple O(n²) — fine for typical counts < 100)
            bool found = false;
            for (uint256 j = 0; j < evalCount; j++) {
                if (evaluators[j] == seal.evaluator) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                evaluators[evalCount] = seal.evaluator;
                evalCount++;
            }
        }

        profile.uniqueEvaluators = evalCount;

        if (profile.activeSeals > 0) {
            profile.averageScore = scoreSum / profile.activeSeals;
        }

        for (uint256 q = 0; q < 4; q++) {
            if (profile.quadrantCounts[q] > 0) {
                profile.quadrantAvgScores[q] = qScoreSums[q] / profile.quadrantCounts[q];
            }
        }
    }

    /**
     * @notice Batch get reputation profiles for multiple subjects
     * @dev Single RPC call to fetch profiles for up to 50 subjects.
     *      Critical for swarm coordinators doing agent selection.
     * @param subjects Array of addresses to profile
     * @return profiles Array of reputation profiles
     */
    function batchGetProfiles(address[] calldata subjects)
        external
        view
        returns (ReputationProfile[] memory profiles)
    {
        require(subjects.length <= 50, "Max 50 subjects per batch");
        profiles = new ReputationProfile[](subjects.length);

        for (uint256 i = 0; i < subjects.length; i++) {
            profiles[i] = this.getReputationProfile(subjects[i]);
        }
    }

    /**
     * @notice Get evaluator credibility profile
     * @dev Analyzes the seals an evaluator has issued to assess their credibility.
     *      High revocation rate or extreme scores may indicate unreliable evaluator.
     * @param evaluator Address of the evaluator
     * @return profile Evaluator credibility metrics
     */
    function getEvaluatorProfile(address evaluator) external view returns (EvaluatorProfile memory profile) {
        profile.evaluator = evaluator;
        uint256[] memory sealIds = registry.getEvaluatorSeals(evaluator);
        profile.totalIssued = sealIds.length;

        if (sealIds.length == 0) return profile;

        address[] memory subjects = new address[](sealIds.length);
        uint256 subjectCount = 0;
        uint256 scoreSum = 0;
        uint256 scoreSumSq = 0;
        uint256 activeCount = 0;

        for (uint256 i = 0; i < sealIds.length; i++) {
            SealRegistry.Seal memory seal = registry.getSeal(sealIds[i]);

            if (seal.revoked) {
                profile.revokedCount++;
                continue;
            }

            activeCount++;
            scoreSum += seal.score;
            scoreSumSq += uint256(seal.score) * uint256(seal.score);

            uint8 q = uint8(seal.quadrant);
            profile.quadrantCounts[q]++;

            // Count unique subjects
            bool found = false;
            for (uint256 j = 0; j < subjectCount; j++) {
                if (subjects[j] == seal.subject) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                subjects[subjectCount] = seal.subject;
                subjectCount++;
            }
        }

        profile.uniqueSubjects = subjectCount;

        if (activeCount > 0) {
            profile.averageScoreGiven = scoreSum / activeCount;
            // Variance = E[X²] - E[X]² (scaled by 100 for precision)
            uint256 meanSq = (scoreSum * scoreSum) / (activeCount * activeCount);
            uint256 meanOfSq = scoreSumSq / activeCount;
            if (meanOfSq >= meanSq) {
                profile.scoreVariance = ((meanOfSq - meanSq) * 100);
            }
        }
    }

    /**
     * @notice Compare multiple subjects' reputations, ranked by score
     * @dev Returns subjects sorted by their active seal average score (descending).
     *      Optionally filter by quadrant. Used for agent selection in task assignment.
     * @param subjects Array of addresses to compare
     * @param filterQuadrant Whether to filter by quadrant
     * @param quadrant Which quadrant to filter (only used if filterQuadrant is true)
     * @return results Ranked comparison results
     */
    function compareReputation(address[] calldata subjects, bool filterQuadrant, SealRegistry.Quadrant quadrant)
        external
        view
        returns (ComparisonResult[] memory results)
    {
        require(subjects.length <= 50, "Max 50 subjects");
        results = new ComparisonResult[](subjects.length);

        for (uint256 i = 0; i < subjects.length; i++) {
            (uint256 avgScore, uint256 activeCount,) = registry.compositeScore(subjects[i], filterQuadrant, quadrant);

            results[i] = ComparisonResult({
                subject: subjects[i],
                overallScore: avgScore,
                activeCount: activeCount,
                rank: 0 // filled below
            });
        }

        // Simple insertion sort by score descending (fine for ≤50 items)
        for (uint256 i = 1; i < results.length; i++) {
            ComparisonResult memory key = results[i];
            int256 j = int256(i) - 1;
            while (j >= 0 && results[uint256(j)].overallScore < key.overallScore) {
                results[uint256(j) + 1] = results[uint256(j)];
                j--;
            }
            results[uint256(j + 1)] = key;
        }

        // Assign ranks (1-based)
        for (uint256 i = 0; i < results.length; i++) {
            results[i].rank = i + 1;
        }
    }

    /**
     * @notice Get seal summaries for a subject (compact batch read)
     * @dev Returns up to `limit` most recent seals starting from `offset`.
     *      Useful for paginated reputation views in dashboards.
     * @param subject Address to query
     * @param offset Starting index in the subject's seal list
     * @param limit Maximum number of seals to return
     * @return summaries Array of compact seal summaries
     */
    function getSealSummaries(address subject, uint256 offset, uint256 limit)
        external
        view
        returns (SealSummary[] memory summaries)
    {
        uint256[] memory sealIds = registry.getSubjectSeals(subject);

        if (offset >= sealIds.length) {
            return new SealSummary[](0);
        }

        uint256 end = offset + limit;
        if (end > sealIds.length) end = sealIds.length;
        uint256 count = end - offset;

        summaries = new SealSummary[](count);

        for (uint256 i = 0; i < count; i++) {
            SealRegistry.Seal memory seal = registry.getSeal(sealIds[offset + i]);
            bool isActive = !seal.revoked && (seal.expiresAt == 0 || block.timestamp <= seal.expiresAt);

            summaries[i] = SealSummary({
                sealId: sealIds[offset + i],
                sealType: seal.sealType,
                evaluator: seal.evaluator,
                quadrant: uint8(seal.quadrant),
                score: seal.score,
                issuedAt: seal.issuedAt,
                active: isActive
            });
        }
    }

    /**
     * @notice Build trust graph edges for a set of addresses
     * @dev Discovers evaluator→subject relationships and aggregates metrics.
     *      Returns edges where the evaluator has issued ≥1 seal to the subject.
     *      Max 20 addresses to keep gas reasonable.
     * @param addresses Set of addresses to analyze relationships between
     * @return edges Array of trust edges found
     */
    function getTrustGraph(address[] calldata addresses) external view returns (TrustEdge[] memory edges) {
        require(addresses.length <= 20, "Max 20 addresses for trust graph");

        // Pre-allocate maximum possible edges (n * (n-1))
        uint256 maxEdges = addresses.length * (addresses.length - 1);
        TrustEdge[] memory tempEdges = new TrustEdge[](maxEdges);
        uint256 edgeCount = 0;

        for (uint256 i = 0; i < addresses.length; i++) {
            uint256[] memory evalSeals = registry.getEvaluatorSeals(addresses[i]);

            for (uint256 j = 0; j < addresses.length; j++) {
                if (i == j) continue;

                // Count seals from addresses[i] → addresses[j]
                uint256 sealCount = 0;
                uint256 scoreSum = 0;
                uint48 firstTs = type(uint48).max;
                uint48 lastTs = 0;

                for (uint256 k = 0; k < evalSeals.length; k++) {
                    SealRegistry.Seal memory seal = registry.getSeal(evalSeals[k]);
                    if (seal.subject != addresses[j]) continue;
                    if (seal.revoked) continue;

                    sealCount++;
                    scoreSum += seal.score;
                    if (seal.issuedAt < firstTs) firstTs = seal.issuedAt;
                    if (seal.issuedAt > lastTs) lastTs = seal.issuedAt;
                }

                if (sealCount > 0) {
                    tempEdges[edgeCount] = TrustEdge({
                        evaluator: addresses[i],
                        subject: addresses[j],
                        sealCount: sealCount,
                        averageScore: scoreSum / sealCount,
                        firstSeal: firstTs,
                        lastSeal: lastTs
                    });
                    edgeCount++;
                }
            }
        }

        // Copy to right-sized array
        edges = new TrustEdge[](edgeCount);
        for (uint256 i = 0; i < edgeCount; i++) {
            edges[i] = tempEdges[i];
        }
    }

    /**
     * @notice Get reputation for a subject filtered by seal type
     * @dev Returns score breakdown per seal type for the given types.
     *      Useful for matching workers to tasks by specific capabilities.
     * @param subject Address to query
     * @param sealTypes Array of seal types to check
     * @return scores Array of average scores per seal type
     * @return counts Array of active seal counts per seal type
     */
    function getReputationByTypes(address subject, bytes32[] calldata sealTypes)
        external
        view
        returns (uint256[] memory scores, uint256[] memory counts)
    {
        require(sealTypes.length <= 13, "Max 13 seal types");
        scores = new uint256[](sealTypes.length);
        counts = new uint256[](sealTypes.length);

        for (uint256 i = 0; i < sealTypes.length; i++) {
            (scores[i], counts[i]) = registry.reputationByType(subject, sealTypes[i]);
        }
    }

    /**
     * @notice Count seals issued within a time window
     * @dev Useful for reputation velocity analysis — are new seals coming in faster?
     * @param subject Address to check
     * @param since Timestamp to count from
     * @return total Total seals since timestamp
     * @return positive Seals with score >= 50
     * @return negative Seals with score < 50
     */
    function sealsSince(address subject, uint48 since)
        external
        view
        returns (uint256 total, uint256 positive, uint256 negative)
    {
        uint256[] memory sealIds = registry.getSubjectSeals(subject);

        for (uint256 i = 0; i < sealIds.length; i++) {
            SealRegistry.Seal memory seal = registry.getSeal(sealIds[i]);
            if (seal.revoked) continue;
            if (seal.issuedAt < since) continue;

            total++;
            if (seal.score >= 50) {
                positive++;
            } else {
                negative++;
            }
        }
    }

    /**
     * @notice Check if a subject has minimum reputation thresholds
     * @dev Used by task assigners to gate workers: "must have ≥3 SKILLFUL seals with avg ≥70"
     * @param subject Address to check
     * @param sealType Required seal type
     * @param minCount Minimum number of active seals of this type
     * @param minAvgScore Minimum average score across those seals
     * @return meets True if subject meets all thresholds
     * @return actualCount Actual count of matching seals
     * @return actualAvg Actual average score
     */
    function meetsReputationThreshold(address subject, bytes32 sealType, uint256 minCount, uint256 minAvgScore)
        external
        view
        returns (bool meets, uint256 actualCount, uint256 actualAvg)
    {
        (actualAvg, actualCount) = registry.reputationByType(subject, sealType);
        meets = actualCount >= minCount && actualAvg >= minAvgScore;
    }
}
