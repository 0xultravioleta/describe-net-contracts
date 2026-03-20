// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SealRegistry.sol";

/**
 * @title SealAggregator
 * @author describe-net
 * @dev Cross-registry reputation aggregation and portable trust scores
 *
 * In a multi-registry world (different protocols, different chains),
 * entities accumulate reputation fragments across multiple SealRegistries.
 * The SealAggregator consolidates these into unified trust profiles.
 *
 * Use cases:
 * 1. Worker applies to Execution Market — aggregate their seals from
 *    EM's registry + MoltX's registry + any other protocol
 * 2. Agent needs a composite reputation for routing — query one contract
 *    instead of N registries
 * 3. Portable credentials — carry your reputation across platforms
 *
 * Features:
 * - Multi-registry aggregation (up to 10 registries)
 * - Weighted registry contributions (some registries are more trusted)
 * - Category-specific aggregation (SKILLFUL across all registries)
 * - Trust tier classification (Newcomer → Trusted → Established → Elite)
 * - Batch subject aggregation for leaderboards
 *
 * All functions are view — no state modifications except admin config.
 */
contract SealAggregator {
    // ─── Storage ────────────────────────────────────────────

    /// @dev Registry with its trust weight (0-100)
    struct RegistryEntry {
        SealRegistry registry;
        uint8 weight; // 0-100, default 100
        string label; // Human-readable name
        bool active;
    }

    /// @dev Aggregated reputation profile for a subject
    struct AggregatedProfile {
        address subject;
        uint256 totalSeals;
        uint256 activeSeals;
        uint256 registriesPresent; // How many registries have seals for this subject
        uint256 weightedScore; // 0-10000 (basis points)
        TrustTier tier;
    }

    /// @dev Category-specific aggregation result
    struct CategoryScore {
        bytes32 sealType;
        uint256 totalSeals;
        uint256 weightedScore; // 0-10000
        uint256 registriesPresent;
    }

    /// @dev Trust tier classification
    enum TrustTier {
        Newcomer,    // 0 seals or very low score
        Emerging,    // Some seals, building reputation
        Trusted,     // Solid reputation, multiple sources
        Established, // Strong reputation, multi-registry
        Elite        // Top-tier, extensively verified
    }

    /// @dev Comparison result between two subjects
    struct ComparisonResult {
        address subjectA;
        address subjectB;
        uint256 scoreA;
        uint256 scoreB;
        uint256 sealsA;
        uint256 sealsB;
        TrustTier tierA;
        TrustTier tierB;
    }

    // State
    RegistryEntry[] public registries;
    address public admin;

    // Tier thresholds (configurable)
    uint256 public tierEmerging = 3;     // 3+ seals
    uint256 public tierTrusted = 10;      // 10+ seals
    uint256 public tierEstablished = 25;  // 25+ seals, 2+ registries
    uint256 public tierElite = 50;        // 50+ seals, 3+ registries

    // ─── Events ─────────────────────────────────────────────

    event RegistryAdded(uint256 indexed index, address indexed registry, uint8 weight, string label);
    event RegistryUpdated(uint256 indexed index, uint8 newWeight, bool active);
    event TierThresholdsUpdated(uint256 emerging, uint256 trusted, uint256 established, uint256 elite);

    // ─── Errors ─────────────────────────────────────────────

    error NotAdmin();
    error InvalidWeight();
    error InvalidIndex();
    error TooManyRegistries();
    error InvalidThresholds();

    // ─── Modifiers ──────────────────────────────────────────

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    // ─── Constructor ────────────────────────────────────────

    constructor() {
        admin = msg.sender;
    }

    // ─── Admin Functions ────────────────────────────────────

    function addRegistry(
        SealRegistry registry,
        uint8 weight,
        string calldata label
    ) external onlyAdmin {
        if (registries.length >= 10) revert TooManyRegistries();
        if (weight > 100) revert InvalidWeight();

        registries.push(RegistryEntry({
            registry: registry,
            weight: weight,
            label: label,
            active: true
        }));

        emit RegistryAdded(registries.length - 1, address(registry), weight, label);
    }

    function updateRegistry(
        uint256 index,
        uint8 newWeight,
        bool active
    ) external onlyAdmin {
        if (index >= registries.length) revert InvalidIndex();
        if (newWeight > 100) revert InvalidWeight();

        registries[index].weight = newWeight;
        registries[index].active = active;

        emit RegistryUpdated(index, newWeight, active);
    }

    function setTierThresholds(
        uint256 emerging,
        uint256 trusted,
        uint256 established,
        uint256 elite
    ) external onlyAdmin {
        if (emerging >= trusted || trusted >= established || established >= elite) {
            revert InvalidThresholds();
        }
        tierEmerging = emerging;
        tierTrusted = trusted;
        tierEstablished = established;
        tierElite = elite;
        emit TierThresholdsUpdated(emerging, trusted, established, elite);
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
    }

    // ─── Core Aggregation ───────────────────────────────────

    function getAggregatedProfile(
        address subject
    ) external view returns (AggregatedProfile memory profile) {
        profile.subject = subject;
        uint256 totalWeightedScore = 0;
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < registries.length; i++) {
            if (!registries[i].active) continue;

            SealRegistry reg = registries[i].registry;
            uint256[] memory sealIds = reg.getSubjectSeals(subject);

            if (sealIds.length > 0) {
                profile.registriesPresent++;
                profile.totalSeals += sealIds.length;

                // Count active and compute average score
                (uint256 active, uint256 avgScore) = _analyzeSeals(reg, sealIds);
                profile.activeSeals += active;

                if (active > 0) {
                    totalWeightedScore += avgScore * registries[i].weight;
                    totalWeight += registries[i].weight;
                }
            }
        }

        if (totalWeight > 0) {
            profile.weightedScore = totalWeightedScore / totalWeight;
        }

        profile.tier = _classifyTier(
            profile.activeSeals,
            profile.registriesPresent,
            profile.weightedScore
        );
    }

    function getCategoryScore(
        address subject,
        bytes32 sealType
    ) external view returns (CategoryScore memory score) {
        score.sealType = sealType;
        uint256 totalWeightedScore = 0;
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < registries.length; i++) {
            if (!registries[i].active) continue;

            SealRegistry reg = registries[i].registry;
            uint256[] memory sealIds = reg.getSubjectSeals(subject);
            bool registryContributed = false;

            for (uint256 j = 0; j < sealIds.length; j++) {
                SealRegistry.Seal memory seal = reg.getSeal(sealIds[j]);
                if (seal.sealType == sealType && !seal.revoked) {
                    if (seal.expiresAt == 0 || seal.expiresAt > block.timestamp) {
                        score.totalSeals++;
                        totalWeightedScore += uint256(seal.score) * 100 * registries[i].weight;
                        totalWeight += registries[i].weight;
                        registryContributed = true;
                    }
                }
            }

            if (registryContributed) {
                score.registriesPresent++;
            }
        }

        if (totalWeight > 0) {
            score.weightedScore = totalWeightedScore / totalWeight;
        }
    }

    function batchAggregateProfiles(
        address[] calldata subjects
    ) external view returns (AggregatedProfile[] memory profiles) {
        profiles = new AggregatedProfile[](subjects.length);
        for (uint256 i = 0; i < subjects.length; i++) {
            profiles[i] = this.getAggregatedProfile(subjects[i]);
        }
    }

    function compareSubjects(
        address a,
        address b
    ) external view returns (ComparisonResult memory result) {
        AggregatedProfile memory profileA = this.getAggregatedProfile(a);
        AggregatedProfile memory profileB = this.getAggregatedProfile(b);

        result.subjectA = a;
        result.subjectB = b;
        result.scoreA = profileA.weightedScore;
        result.scoreB = profileB.weightedScore;
        result.sealsA = profileA.activeSeals;
        result.sealsB = profileB.activeSeals;
        result.tierA = profileA.tier;
        result.tierB = profileB.tier;
    }

    // ─── View Helpers ───────────────────────────────────────

    function activeRegistryCount() external view returns (uint256 count) {
        for (uint256 i = 0; i < registries.length; i++) {
            if (registries[i].active) count++;
        }
    }

    function totalRegistries() external view returns (uint256) {
        return registries.length;
    }

    function hasMultiRegistryPresence(
        address subject,
        uint256 minRegistries
    ) external view returns (bool) {
        uint256 count = 0;
        for (uint256 i = 0; i < registries.length; i++) {
            if (!registries[i].active) continue;
            uint256[] memory sealIds = registries[i].registry.getSubjectSeals(subject);
            if (sealIds.length > 0) {
                count++;
                if (count >= minRegistries) return true;
            }
        }
        return false;
    }

    function getTrustTier(address subject) external view returns (TrustTier) {
        AggregatedProfile memory profile = this.getAggregatedProfile(subject);
        return profile.tier;
    }

    // ─── Internal ───────────────────────────────────────────

    function _analyzeSeals(
        SealRegistry reg,
        uint256[] memory sealIds
    ) internal view returns (uint256 active, uint256 avgScore) {
        uint256 scoreSum = 0;
        for (uint256 i = 0; i < sealIds.length; i++) {
            SealRegistry.Seal memory seal = reg.getSeal(sealIds[i]);
            if (!seal.revoked && (seal.expiresAt == 0 || seal.expiresAt > block.timestamp)) {
                active++;
                scoreSum += seal.score;
            }
        }
        if (active > 0) {
            avgScore = (scoreSum * 100) / active; // basis points
        }
    }

    function _classifyTier(
        uint256 activeSeals,
        uint256 registriesPresent,
        uint256 weightedScore
    ) internal view returns (TrustTier) {
        if (activeSeals >= tierElite && registriesPresent >= 3 && weightedScore >= 7000) {
            return TrustTier.Elite;
        }
        if (activeSeals >= tierEstablished && registriesPresent >= 2 && weightedScore >= 5000) {
            return TrustTier.Established;
        }
        if (activeSeals >= tierTrusted && weightedScore >= 4000) {
            return TrustTier.Trusted;
        }
        if (activeSeals >= tierEmerging) {
            return TrustTier.Emerging;
        }
        return TrustTier.Newcomer;
    }
}
