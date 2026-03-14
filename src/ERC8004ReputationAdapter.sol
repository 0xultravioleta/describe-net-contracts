// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IERC8004ReputationAdapter.sol";
import "./interfaces/IIdentityRegistry.sol";
import "./SealRegistry.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title ERC8004ReputationAdapter
 * @dev Adapter contract that provides ERC-8004 compatibility for the describe-net SealRegistry
 * @dev This contract wraps an existing SealRegistry deployment and maps ERC-8004's giveFeedback()
 *      to SealRegistry's issueSeal() system with proper tag-to-type/quadrant mapping
 */
contract ERC8004ReputationAdapter is IERC8004ReputationAdapter {
    /// @dev The wrapped SealRegistry contract
    SealRegistry public immutable sealRegistry;

    /// @dev The identity registry for agent lookups
    IIdentityRegistry public immutable identityRegistry;

    /// @dev Mapping from tag1 strings to seal type hashes
    mapping(string => bytes32) public tag1ToSealType;

    /// @dev Mapping from seal type hashes to tag1 strings
    mapping(bytes32 => string) public sealTypeToTag1;

    /// @dev Mapping from tag2 strings to quadrant enum values
    mapping(string => SealRegistry.Quadrant) public tag2ToQuadrant;

    /// @dev Mapping from quadrant enum values to tag2 strings
    mapping(SealRegistry.Quadrant => string) public quadrantToTag2;

    /// @dev Mapping from seal ID to additional ERC-8004 metadata
    mapping(uint256 => ERC8004Metadata) private _erc8004Metadata;

    /**
     * @dev Additional metadata stored for ERC-8004 compatibility
     * @param originalSubmitter The original caller who submitted the feedback
     * @param valueDecimals Original value decimals from ERC-8004 call
     * @param endpoint Endpoint URL from ERC-8004 call
     * @param feedbackURI Feedback URI from ERC-8004 call
     */
    struct ERC8004Metadata {
        address originalSubmitter;
        uint8 valueDecimals;
        string endpoint;
        string feedbackURI;
    }

    /**
     * @dev Constructor
     * @param _sealRegistry Address of the existing SealRegistry contract
     */
    constructor(address _sealRegistry) {
        sealRegistry = SealRegistry(_sealRegistry);
        identityRegistry = sealRegistry.identityRegistry();
        _initializeMappings();
    }

    /**
     * @dev Initialize the mappings between ERC-8004 tags and SealRegistry types/quadrants
     */
    function _initializeMappings() private {
        // Tag1 → SealType mappings (all 13 seal types)
        _mapTag1ToSealType("SKILLFUL", sealRegistry.SKILLFUL());
        _mapTag1ToSealType("RELIABLE", sealRegistry.RELIABLE());
        _mapTag1ToSealType("THOROUGH", sealRegistry.THOROUGH());
        _mapTag1ToSealType("ENGAGED", sealRegistry.ENGAGED());
        _mapTag1ToSealType("HELPFUL", sealRegistry.HELPFUL());
        _mapTag1ToSealType("CURIOUS", sealRegistry.CURIOUS());
        _mapTag1ToSealType("FAIR", sealRegistry.FAIR());
        _mapTag1ToSealType("ACCURATE", sealRegistry.ACCURATE());
        _mapTag1ToSealType("RESPONSIVE", sealRegistry.RESPONSIVE());
        _mapTag1ToSealType("ETHICAL", sealRegistry.ETHICAL());
        _mapTag1ToSealType("CREATIVE", sealRegistry.CREATIVE());
        _mapTag1ToSealType("PROFESSIONAL", sealRegistry.PROFESSIONAL());
        _mapTag1ToSealType("FRIENDLY", sealRegistry.FRIENDLY());

        // Tag2 → Quadrant mappings
        tag2ToQuadrant["H2H"] = SealRegistry.Quadrant.H2H;
        tag2ToQuadrant["H2A"] = SealRegistry.Quadrant.H2A;
        tag2ToQuadrant["A2H"] = SealRegistry.Quadrant.A2H;
        tag2ToQuadrant["A2A"] = SealRegistry.Quadrant.A2A;

        // Reverse mappings
        quadrantToTag2[SealRegistry.Quadrant.H2H] = "H2H";
        quadrantToTag2[SealRegistry.Quadrant.H2A] = "H2A";
        quadrantToTag2[SealRegistry.Quadrant.A2H] = "A2H";
        quadrantToTag2[SealRegistry.Quadrant.A2A] = "A2A";
    }

    /**
     * @dev Helper function to set up bidirectional tag1/sealType mappings
     * @param tag The string tag
     * @param sealType The bytes32 seal type hash
     */
    function _mapTag1ToSealType(string memory tag, bytes32 sealType) private {
        tag1ToSealType[tag] = sealType;
        sealTypeToTag1[sealType] = tag;
    }

    /**
     * @dev Give feedback to an agent in ERC-8004 format
     * @param agentId The ID of the agent receiving feedback
     * @param value The feedback value (will be clamped to 0-100 range)
     * @param valueDecimals Decimals for the value (for compatibility, not used in scoring)
     * @param tag1 Primary tag that maps to seal type (e.g., "SKILLFUL", "RELIABLE")
     * @param tag2 Secondary tag that maps to quadrant (e.g., "H2H", "H2A", "A2H", "A2A")
     * @param endpoint Endpoint URL (stored but not processed)
     * @param feedbackURI URI for additional feedback data
     * @param feedbackHash Hash of the feedback data (maps to evidenceHash)
     * @return sealId The ID of the created seal in the SealRegistry
     */
    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external returns (uint256 sealId) {
        // Validate inputs
        _validateFeedbackInputs(agentId, tag1, tag2);

        // Convert and issue seal
        sealId = _issueSealFromFeedback(agentId, value, tag1, tag2, feedbackHash);

        // Store ERC-8004 metadata
        _erc8004Metadata[sealId] = ERC8004Metadata({
            originalSubmitter: msg.sender, valueDecimals: valueDecimals, endpoint: endpoint, feedbackURI: feedbackURI
        });

        // Emit ERC-8004 compatible event
        emit FeedbackGiven(agentId, msg.sender, value, tag1, tag2, sealId);
    }

    /**
     * @dev Validate feedback inputs
     * @param agentId The agent ID
     * @param tag1 The seal type tag
     * @param tag2 The quadrant tag
     */
    function _validateFeedbackInputs(uint256 agentId, string calldata tag1, string calldata tag2) internal view {
        // Validate tags
        if (tag1ToSealType[tag1] == bytes32(0)) revert InvalidTag1(tag1);
        if (!(keccak256(bytes(tag2)) == keccak256("H2H") || keccak256(bytes(tag2)) == keccak256("H2A")
                    || keccak256(bytes(tag2)) == keccak256("A2H") || keccak256(bytes(tag2)) == keccak256("A2A"))) {
            revert InvalidTag2(tag2);
        }

        // For non-zero agent IDs, check self-feedback prevention
        if (agentId > 0) {
            IIdentityRegistry.AgentInfo memory agentInfo = identityRegistry.getAgent(agentId);
            if (msg.sender == agentInfo.agentAddress) {
                revert SelfFeedbackNotAllowed(msg.sender);
            }
        }
    }

    /**
     * @dev Issue seal from feedback parameters
     * @param agentId The agent ID
     * @param value The feedback value
     * @param tag1 The seal type tag
     * @param tag2 The quadrant tag
     * @param feedbackHash The feedback hash
     * @return sealId The created seal ID
     */
    function _issueSealFromFeedback(
        uint256 agentId,
        int128 value,
        string calldata tag1,
        string calldata tag2,
        bytes32 feedbackHash
    ) internal returns (uint256 sealId) {
        bytes32 sealType = tag1ToSealType[tag1];
        SealRegistry.Quadrant quadrant = tag2ToQuadrant[tag2];

        // Convert value to score (clamp to 0-100)
        uint8 score;
        if (value < 0) {
            score = 0;
        } else if (value > 100) {
            score = 100;
        } else {
            score = uint8(uint128(value));
        }

        // Issue the seal based on quadrant
        if (quadrant == SealRegistry.Quadrant.H2H) {
            // For H2H, if agentId is 0, use msg.sender as subject (self-evaluation prevention is checked earlier)
            // If agentId is provided, use the agent address as subject
            address subject = msg.sender; // Default to evaluating self, but this was prevented earlier
            if (agentId > 0) {
                IIdentityRegistry.AgentInfo memory agentInfo = identityRegistry.getAgent(agentId);
                if (agentInfo.agentId > 0) {
                    subject = agentInfo.agentAddress;
                }
            }
            sealId = sealRegistry.issueSealH2H(subject, sealType, score, feedbackHash);
        } else if (quadrant == SealRegistry.Quadrant.H2A) {
            // For H2A, we must have a valid agent ID
            sealId = sealRegistry.issueSealH2A(agentId, sealType, score, feedbackHash);
        } else if (quadrant == SealRegistry.Quadrant.A2H) {
            // For A2H, the current caller (msg.sender) must be a registered agent
            // and the agentId parameter specifies the subject being evaluated
            address subject;
            if (agentId > 0) {
                IIdentityRegistry.AgentInfo memory agentInfo = identityRegistry.getAgent(agentId);
                if (agentInfo.agentId > 0) {
                    subject = agentInfo.agentAddress;
                } else {
                    revert("Agent not found");
                }
            } else {
                // If no agentId provided, this is invalid for A2H
                revert("agentId required for A2H");
            }

            // The adapter cannot directly call issueSealA2H because it's not a registered agent
            // We need to use a different approach or modify the design
            // For now, let's revert with a clear message
            revert("A2H not supported via adapter - agent must call SealRegistry directly");
        } else {
            // A2A - not supported via adapter for same reasons as A2H
            revert("A2A not supported via adapter - agent must call SealRegistry directly");
        }
    }

    /**
     * @dev Get feedback data in ERC-8004 format from a seal ID
     * @param sealId The ID of the seal to convert to ERC-8004 format
     * @return feedback The feedback data in ERC-8004 format
     */
    function getFeedbackAsERC8004(uint256 sealId) external view returns (ERC8004Feedback memory feedback) {
        return sealToFeedback(sealId);
    }

    /**
     * @dev Convert a seal to ERC-8004 feedback format
     * @param sealId The ID of the seal to convert
     * @return feedback The feedback data in ERC-8004 format
     */
    function sealToFeedback(uint256 sealId) public view returns (ERC8004Feedback memory feedback) {
        // Get seal data from SealRegistry
        SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);

        // Get ERC-8004 metadata
        ERC8004Metadata memory metadata = _erc8004Metadata[sealId];

        // Find agent ID for the subject
        IIdentityRegistry.AgentInfo memory agentInfo = identityRegistry.resolveByAddress(seal.subject);
        uint256 agentId = agentInfo.agentId;

        // If subject is not a registered agent, try to infer from context
        if (agentId == 0) {
            // This could be an H2H seal where subject is not an agent
            // In this case, we'll use 0 as agentId to indicate it's not an agent
        }

        // Convert seal data to ERC-8004 format
        feedback = ERC8004Feedback({
            agentId: agentId,
            submitter: metadata.originalSubmitter != address(0) ? metadata.originalSubmitter : seal.evaluator,
            value: int128(uint128(seal.score)), // Convert uint8 score back to int128
            valueDecimals: metadata.valueDecimals,
            tag1: sealTypeToTag1[seal.sealType],
            tag2: quadrantToTag2[seal.quadrant],
            endpoint: metadata.endpoint,
            feedbackURI: metadata.feedbackURI,
            feedbackHash: seal.evidenceHash,
            timestamp: seal.issuedAt
        });
    }

    /**
     * @dev Convert ERC-8004 feedback parameters to seal parameters
     * @param agentId The ID of the agent receiving feedback
     * @param value The feedback value
     * @param tag1 Primary tag (seal type)
     * @param tag2 Secondary tag (quadrant)
     * @param feedbackHash Hash of the feedback data
     * @return subject The subject address
     * @return sealType The seal type hash
     * @return quadrant The quadrant enum value
     * @return score The score (0-100)
     * @return evidenceHash The evidence hash
     */
    function feedbackToSeal(
        uint256 agentId,
        int128 value,
        string calldata tag1,
        string calldata tag2,
        bytes32 feedbackHash
    ) public view returns (address subject, bytes32 sealType, uint8 quadrant, uint8 score, bytes32 evidenceHash) {
        // Map tag1 to sealType
        sealType = tag1ToSealType[tag1];

        // Map tag2 to quadrant
        SealRegistry.Quadrant quadrantEnum = tag2ToQuadrant[tag2];
        quadrant = uint8(quadrantEnum);

        // Convert value to score (clamp to 0-100)
        if (value < 0) {
            score = 0;
        } else if (value > 100) {
            score = 100;
        } else {
            score = uint8(uint128(value));
        }

        // Get subject address
        if (agentId > 0) {
            IIdentityRegistry.AgentInfo memory agentInfo = identityRegistry.getAgent(agentId);
            subject = agentInfo.agentAddress;
        } else {
            // If agentId is 0, this is used for H2H or A2H where we need a different approach
            // For now, we'll leave it as address(0) and let the caller handle it
            subject = address(0);
        }

        // Map feedbackHash to evidenceHash
        evidenceHash = feedbackHash;
    }

    /**
     * @dev Check if a tag1 (seal type) is valid
     * @param tag1 The tag1 to check
     * @return True if valid, false otherwise
     */
    function isValidTag1(string calldata tag1) external view returns (bool) {
        return tag1ToSealType[tag1] != bytes32(0);
    }

    /**
     * @dev Check if a tag2 (quadrant) is valid
     * @param tag2 The tag2 to check
     * @return True if valid, false otherwise
     */
    function isValidTag2(string calldata tag2) external pure returns (bool) {
        return (keccak256(bytes(tag2)) == keccak256("H2H") || keccak256(bytes(tag2)) == keccak256("H2A")
                || keccak256(bytes(tag2)) == keccak256("A2H") || keccak256(bytes(tag2)) == keccak256("A2A"));
    }
}
