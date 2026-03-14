// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IERC8004ReputationAdapter
 * @dev Interface for ERC-8004 compatibility layer over the describe-net SealRegistry
 * @dev This adapter maps ERC-8004's giveFeedback() to SealRegistry's issueSeal() system
 */
interface IERC8004ReputationAdapter {
    /**
     * @dev Struct representing feedback in ERC-8004 format
     * @param agentId The ID of the agent receiving feedback
     * @param submitter The address of the feedback submitter
     * @param value The feedback value (int128, clamped to 0-100)
     * @param valueDecimals Decimals for the value (preserved for compatibility)
     * @param tag1 Primary tag (maps to seal type)
     * @param tag2 Secondary tag (maps to quadrant)
     * @param endpoint Endpoint URL (preserved for compatibility)
     * @param feedbackURI URI for additional feedback data
     * @param feedbackHash Hash of the feedback data
     * @param timestamp When the feedback was given
     */
    struct ERC8004Feedback {
        uint256 agentId;
        address submitter;
        int128 value;
        uint8 valueDecimals;
        string tag1;
        string tag2;
        string endpoint;
        string feedbackURI;
        bytes32 feedbackHash;
        uint256 timestamp;
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
    ) external returns (uint256 sealId);

    /**
     * @dev Get feedback data in ERC-8004 format from a seal ID
     * @param sealId The ID of the seal to convert to ERC-8004 format
     * @return feedback The feedback data in ERC-8004 format
     */
    function getFeedbackAsERC8004(uint256 sealId) external view returns (ERC8004Feedback memory feedback);

    /**
     * @dev Convert a seal to ERC-8004 feedback format
     * @param sealId The ID of the seal to convert
     * @return feedback The feedback data in ERC-8004 format
     */
    function sealToFeedback(uint256 sealId) external view returns (ERC8004Feedback memory feedback);

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
    ) external view returns (address subject, bytes32 sealType, uint8 quadrant, uint8 score, bytes32 evidenceHash);

    /**
     * @dev Check if a tag1 (seal type) is valid
     * @param tag1 The tag1 to check
     * @return True if valid, false otherwise
     */
    function isValidTag1(string calldata tag1) external view returns (bool);

    /**
     * @dev Check if a tag2 (quadrant) is valid
     * @param tag2 The tag2 to check
     * @return True if valid, false otherwise
     */
    function isValidTag2(string calldata tag2) external view returns (bool);

    /// @dev Events matching ERC-8004 format

    /**
     * @dev Emitted when feedback is given in ERC-8004 format
     * @param agentId The ID of the agent receiving feedback
     * @param submitter The address of the feedback submitter
     * @param value The feedback value
     * @param tag1 Primary tag (seal type)
     * @param tag2 Secondary tag (quadrant)
     * @param sealId The ID of the created seal
     */
    event FeedbackGiven(
        uint256 indexed agentId,
        address indexed submitter,
        int128 value,
        string tag1,
        string tag2,
        uint256 indexed sealId
    );

    /// @dev Custom errors

    /**
     * @dev Thrown when an invalid tag1 (seal type) is provided
     * @param tag1 The invalid tag1 that was provided
     */
    error InvalidTag1(string tag1);

    /**
     * @dev Thrown when an invalid tag2 (quadrant) is provided
     * @param tag2 The invalid tag2 that was provided
     */
    error InvalidTag2(string tag2);

    /**
     * @dev Thrown when attempting to give feedback to oneself
     * @param submitter The address attempting self-feedback
     */
    error SelfFeedbackNotAllowed(address submitter);
}
