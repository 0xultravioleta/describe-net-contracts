// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ISealChallenge
 * @dev Interface for the seal challenge/dispute system
 *
 * Allows subjects to challenge seals they consider unfair,
 * and provides a resolution mechanism.
 */
interface ISealChallenge {
    enum ChallengeStatus {
        Pending,    // Challenge submitted, awaiting resolution
        Sustained,  // Challenge upheld — seal revoked or score reduced
        Rejected,   // Challenge rejected — seal stands
        Expired,    // Challenge window expired without resolution
        Withdrawn   // Challenger withdrew the challenge
    }

    struct Challenge {
        uint256 sealId;
        address challenger;
        string reason;
        bytes32 evidenceHash;
        ChallengeStatus status;
        uint48 createdAt;
        uint48 resolvedAt;
        uint48 deadline;
        address resolver;
        string resolution;
    }

    event ChallengeCreated(
        uint256 indexed challengeId,
        uint256 indexed sealId,
        address indexed challenger,
        string reason
    );

    event ChallengeResolved(
        uint256 indexed challengeId,
        ChallengeStatus status,
        address resolver,
        string resolution
    );

    event ChallengeWithdrawn(
        uint256 indexed challengeId,
        address indexed challenger
    );

    function createChallenge(
        uint256 sealId,
        string calldata reason,
        bytes32 evidenceHash
    ) external returns (uint256 challengeId);

    function resolveChallenge(
        uint256 challengeId,
        ChallengeStatus status,
        string calldata resolution
    ) external;

    function withdrawChallenge(uint256 challengeId) external;

    function getChallenge(uint256 challengeId) external view returns (Challenge memory);

    function getChallengesForSeal(uint256 sealId) external view returns (uint256[] memory);

    function getChallengesByChallenger(address challenger) external view returns (uint256[] memory);
}
