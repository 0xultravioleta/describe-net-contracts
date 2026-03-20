// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/ISealChallenge.sol";
import "./SealRegistry.sol";

/**
 * @title SealChallenge
 * @dev Dispute/challenge system for describe.net seals
 *
 * Allows subjects (or their delegates) to challenge seals they consider
 * unfair, inaccurate, or malicious. Provides a structured resolution
 * process with configurable deadlines and resolver roles.
 *
 * Flow:
 *   1. Subject sees unfair seal → creates challenge with reason + evidence
 *   2. Challenge enters Pending state with deadline
 *   3. Authorized resolver reviews challenge
 *   4. Resolver either sustains (seal revoked) or rejects (seal stands)
 *   5. If deadline passes without resolution → challenge expires
 *
 * Design decisions:
 *   - Only the seal's subject (or their delegate) can challenge
 *   - Evaluators cannot be their own resolver (conflict of interest)
 *   - Challenge window: configurable, default 7 days
 *   - Resolution is on-chain for transparency
 *   - Sustained challenges trigger seal revocation in SealRegistry
 *   - No staking required (v1) — prevents griefing through economic barriers
 */
contract SealChallenge is ISealChallenge, AccessControl {
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");

    SealRegistry public immutable sealRegistry;

    uint256 private _challengeCounter;

    /// @dev Default challenge window in seconds (7 days)
    uint48 public challengeWindow = 7 days;

    /// @dev Maximum reason length (gas protection)
    uint256 public constant MAX_REASON_LENGTH = 1000;

    /// @dev Maximum resolution length
    uint256 public constant MAX_RESOLUTION_LENGTH = 2000;

    // Storage
    mapping(uint256 => Challenge) private _challenges;
    mapping(uint256 => uint256[]) private _sealChallenges;    // sealId → challengeIds
    mapping(address => uint256[]) private _challengerHistory;  // challenger → challengeIds

    // Rate limiting: one active challenge per seal per challenger
    mapping(bytes32 => bool) private _activeChallenge; // keccak(sealId, challenger) → active

    constructor(address _sealRegistry) {
        require(_sealRegistry != address(0), "SealChallenge: zero registry");
        sealRegistry = SealRegistry(_sealRegistry);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RESOLVER_ROLE, msg.sender);
    }

    // ─── Challenge Creation ──────────────────────────────────────────

    /**
     * @notice Create a challenge against a seal
     * @param sealId The ID of the seal being challenged
     * @param reason Human-readable reason for the challenge
     * @param evidenceHash Hash of off-chain evidence supporting the challenge
     * @return challengeId The ID of the created challenge
     */
    function createChallenge(
        uint256 sealId,
        string calldata reason,
        bytes32 evidenceHash
    ) external override returns (uint256 challengeId) {
        require(bytes(reason).length > 0, "SealChallenge: empty reason");
        require(bytes(reason).length <= MAX_REASON_LENGTH, "SealChallenge: reason too long");

        // Get the seal from registry
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);

        // Only the subject (person who received the seal) can challenge
        require(msg.sender == seal.subject, "SealChallenge: not subject");

        // Can't challenge revoked seals
        require(!seal.revoked, "SealChallenge: already revoked");

        // Can't challenge expired seals
        if (seal.expiresAt > 0) {
            require(block.timestamp < seal.expiresAt, "SealChallenge: seal expired");
        }

        // Rate limiting: one active challenge per seal per challenger
        bytes32 activeKey = keccak256(abi.encodePacked(sealId, msg.sender));
        require(!_activeChallenge[activeKey], "SealChallenge: active challenge exists");
        _activeChallenge[activeKey] = true;

        challengeId = _challengeCounter++;

        _challenges[challengeId] = Challenge({
            sealId: sealId,
            challenger: msg.sender,
            reason: reason,
            evidenceHash: evidenceHash,
            status: ChallengeStatus.Pending,
            createdAt: uint48(block.timestamp),
            resolvedAt: 0,
            deadline: uint48(block.timestamp) + challengeWindow,
            resolver: address(0),
            resolution: ""
        });

        _sealChallenges[sealId].push(challengeId);
        _challengerHistory[msg.sender].push(challengeId);

        emit ChallengeCreated(challengeId, sealId, msg.sender, reason);
    }

    // ─── Challenge Resolution ────────────────────────────────────────

    /**
     * @notice Resolve a pending challenge
     * @param challengeId The challenge to resolve
     * @param status Must be Sustained or Rejected
     * @param resolution Human-readable resolution explanation
     */
    function resolveChallenge(
        uint256 challengeId,
        ChallengeStatus status,
        string calldata resolution
    ) external override onlyRole(RESOLVER_ROLE) {
        Challenge storage c = _challenges[challengeId];
        require(c.createdAt > 0, "SealChallenge: not found");
        require(c.status == ChallengeStatus.Pending, "SealChallenge: not pending");
        require(
            status == ChallengeStatus.Sustained || status == ChallengeStatus.Rejected,
            "SealChallenge: invalid status"
        );
        require(bytes(resolution).length <= MAX_RESOLUTION_LENGTH, "SealChallenge: resolution too long");

        // Resolver can't be the evaluator of the challenged seal (conflict of interest)
        SealRegistry.Seal memory seal = sealRegistry.getSeal(c.sealId);
        require(msg.sender != seal.evaluator, "SealChallenge: resolver is evaluator");

        c.status = status;
        c.resolvedAt = uint48(block.timestamp);
        c.resolver = msg.sender;
        c.resolution = resolution;

        // Clear active challenge flag
        bytes32 activeKey = keccak256(abi.encodePacked(c.sealId, c.challenger));
        _activeChallenge[activeKey] = false;

        // If sustained, revoke the seal in the registry
        // Note: requires SealChallenge to be granted CHALLENGE_REVOKER_ROLE
        // on SealRegistry via revokeSealByChallenge()
        if (status == ChallengeStatus.Sustained) {
            sealRegistry.revokeSealByChallenge(c.sealId, resolution);
        }

        emit ChallengeResolved(challengeId, status, msg.sender, resolution);
    }

    // ─── Challenge Withdrawal ────────────────────────────────────────

    /**
     * @notice Withdraw a pending challenge
     * @param challengeId The challenge to withdraw
     */
    function withdrawChallenge(uint256 challengeId) external override {
        Challenge storage c = _challenges[challengeId];
        require(c.createdAt > 0, "SealChallenge: not found");
        require(c.challenger == msg.sender, "SealChallenge: not challenger");
        require(c.status == ChallengeStatus.Pending, "SealChallenge: not pending");

        c.status = ChallengeStatus.Withdrawn;
        c.resolvedAt = uint48(block.timestamp);

        // Clear active challenge flag
        bytes32 activeKey = keccak256(abi.encodePacked(c.sealId, c.challenger));
        _activeChallenge[activeKey] = false;

        emit ChallengeWithdrawn(challengeId, msg.sender);
    }

    // ─── Expiry ──────────────────────────────────────────────────────

    /**
     * @notice Mark an expired challenge (anyone can call)
     * @param challengeId The challenge to check/expire
     */
    function expireChallenge(uint256 challengeId) external {
        Challenge storage c = _challenges[challengeId];
        require(c.createdAt > 0, "SealChallenge: not found");
        require(c.status == ChallengeStatus.Pending, "SealChallenge: not pending");
        require(block.timestamp >= c.deadline, "SealChallenge: not expired yet");

        c.status = ChallengeStatus.Expired;
        c.resolvedAt = uint48(block.timestamp);

        // Clear active challenge flag
        bytes32 activeKey = keccak256(abi.encodePacked(c.sealId, c.challenger));
        _activeChallenge[activeKey] = false;
    }

    // ─── Views ───────────────────────────────────────────────────────

    function getChallenge(uint256 challengeId) external view override returns (Challenge memory) {
        require(_challenges[challengeId].createdAt > 0, "SealChallenge: not found");
        return _challenges[challengeId];
    }

    function getChallengesForSeal(uint256 sealId) external view override returns (uint256[] memory) {
        return _sealChallenges[sealId];
    }

    function getChallengesByChallenger(address challenger) external view override returns (uint256[] memory) {
        return _challengerHistory[challenger];
    }

    function totalChallenges() external view returns (uint256) {
        return _challengeCounter;
    }

    function isChallengeActive(uint256 sealId, address challenger) external view returns (bool) {
        bytes32 key = keccak256(abi.encodePacked(sealId, challenger));
        return _activeChallenge[key];
    }

    // ─── Admin ───────────────────────────────────────────────────────

    /**
     * @notice Update the challenge window
     * @param newWindow New window in seconds
     */
    function setChallengeWindow(uint48 newWindow) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newWindow >= 1 days, "SealChallenge: window too short");
        require(newWindow <= 90 days, "SealChallenge: window too long");
        challengeWindow = newWindow;
    }
}
