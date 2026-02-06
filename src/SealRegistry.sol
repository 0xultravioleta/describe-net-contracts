// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IIdentityRegistry.sol";

/**
 * @title SealRegistry
 * @dev Categorical reputation system for the describe.net protocol
 * @dev describe-net is a universal reputation protocol where humans and agents evaluate each other
 * It extends the ERC-8004 agent identity standard with categorical "seals" (like SKILLFUL, RELIABLE, FAIR, etc.)
 * The SealRegistry sits alongside the existing IdentityRegistry and ReputationRegistry contracts
 */
contract SealRegistry is Ownable {
    /// @dev Quadrants define the direction of evaluation
    enum Quadrant {
        H2H, // Human to Human
        H2A, // Human to Agent  
        A2H, // Agent to Human
        A2A  // Agent to Agent
    }

    /**
     * @dev Structure representing a seal issued in the system
     * @param sealType Type identifier for the seal (e.g., keccak256("SKILLFUL"))
     * @param subject Address of the entity receiving the seal
     * @param evaluator Address of the entity issuing the seal
     * @param quadrant Direction of evaluation (H2H, H2A, A2H, A2A)
     * @param evidenceHash Hash of evidence supporting the seal
     * @param score Score from 0-100 representing the strength of the seal
     * @param issuedAt Timestamp when the seal was issued
     * @param expiresAt Timestamp when the seal expires (0 = never expires)
     * @param revoked Whether the seal has been revoked
     */
    struct Seal {
        bytes32 sealType;
        address subject;
        address evaluator;
        Quadrant quadrant;
        bytes32 evidenceHash;
        uint8 score;
        uint48 issuedAt;
        uint48 expiresAt;
        bool revoked;
    }

    /// @dev Counter for seal IDs
    uint256 private _sealIdCounter;

    /// @dev Identity registry interface
    IIdentityRegistry public identityRegistry;

    /// @dev Mapping from seal ID to Seal struct
    mapping(uint256 => Seal) private _seals;

    /// @dev Mapping from seal type to whether it's valid
    mapping(bytes32 => bool) public validSealTypes;

    /// @dev Mapping from address to array of seal IDs they've received
    mapping(address => uint256[]) private _subjectSeals;

    /// @dev Mapping from address to array of seal IDs they've issued
    mapping(address => uint256[]) private _evaluatorSeals;

    /// @dev Mapping from address to seal types they can issue (for agents)
    mapping(address => mapping(bytes32 => bool)) public agentSealDomains;

    /// @dev Initial seal types
    bytes32 public constant SKILLFUL = keccak256("SKILLFUL");
    bytes32 public constant RELIABLE = keccak256("RELIABLE");
    bytes32 public constant THOROUGH = keccak256("THOROUGH");
    bytes32 public constant ENGAGED = keccak256("ENGAGED");
    bytes32 public constant HELPFUL = keccak256("HELPFUL");
    bytes32 public constant CURIOUS = keccak256("CURIOUS");
    bytes32 public constant FAIR = keccak256("FAIR");
    bytes32 public constant ACCURATE = keccak256("ACCURATE");
    bytes32 public constant RESPONSIVE = keccak256("RESPONSIVE");
    bytes32 public constant ETHICAL = keccak256("ETHICAL");
    bytes32 public constant CREATIVE = keccak256("CREATIVE");
    bytes32 public constant PROFESSIONAL = keccak256("PROFESSIONAL");
    bytes32 public constant FRIENDLY = keccak256("FRIENDLY");

    /// @dev Events
    event SealIssued(
        uint256 indexed sealId,
        bytes32 indexed sealType,
        address indexed subject,
        address evaluator,
        Quadrant quadrant,
        uint8 score
    );

    event SealRevoked(uint256 indexed sealId, address indexed evaluator, string reason);

    event SealTypeAdded(bytes32 indexed sealType);

    event AgentDomainsUpdated(address indexed agent, bytes32[] sealTypes);

    /// @dev Custom errors
    
    /// @notice Thrown when attempting to use an unrecognized seal type
    /// @param sealType The invalid seal type hash that was provided
    error InvalidSealType(bytes32 sealType);
    
    /// @notice Thrown when a score exceeds the maximum allowed value of 100
    /// @param score The invalid score that was provided
    error InvalidScore(uint8 score);
    
    /// @notice Thrown when a non-evaluator attempts to modify a seal they didn't issue
    error UnauthorizedEvaluator();
    
    /// @notice Thrown when attempting to access a seal that doesn't exist
    /// @param sealId The seal ID that was not found
    error SealNotFound(uint256 sealId);
    
    /// @notice Thrown when attempting to revoke a seal that is already revoked
    /// @param sealId The seal ID that was already revoked
    error SealAlreadyRevoked(uint256 sealId);
    
    /// @notice Thrown when a non-registered agent attempts agent-only operations
    /// @param agent The address that is not registered as an agent
    error AgentNotRegistered(address agent);
    
    /// @notice Thrown when an agent attempts to issue a seal type outside their registered domains
    /// @param agent The agent address attempting the operation
    /// @param sealType The seal type the agent is not authorized for
    error AgentNotAuthorizedForSealType(address agent, bytes32 sealType);

    /**
     * @dev Constructor
     * @param _identityRegistry Address of the identity registry contract
     */
    constructor(address _identityRegistry) Ownable(msg.sender) {
        identityRegistry = IIdentityRegistry(_identityRegistry);
        _initializeSealTypes();
    }

    /**
     * @dev Initialize the 13 predefined seal types
     */
    function _initializeSealTypes() private {
        // A→H seals
        validSealTypes[SKILLFUL] = true;
        validSealTypes[RELIABLE] = true;
        validSealTypes[THOROUGH] = true;
        validSealTypes[ENGAGED] = true;
        validSealTypes[HELPFUL] = true;
        validSealTypes[CURIOUS] = true;
        
        // H→A seals
        validSealTypes[FAIR] = true;
        validSealTypes[ACCURATE] = true;
        validSealTypes[RESPONSIVE] = true;
        validSealTypes[ETHICAL] = true;
        
        // H→H seals
        validSealTypes[CREATIVE] = true;
        validSealTypes[PROFESSIONAL] = true;
        validSealTypes[FRIENDLY] = true;
    }

    /**
     * @notice Agent issues seal to human (A→H quadrant)
     * @dev Only registered agents can call this. Agent must have the sealType in their registered domains.
     * @param subject Address of the human receiving the seal
     * @param sealType Type of seal being issued (must be a valid seal type)
     * @param score Score from 0-100 representing strength of the evaluation
     * @param evidenceHash Hash of evidence supporting the seal (e.g., IPFS CID)
     * @param expiresAt Expiration timestamp (0 for never expires). Seal expires when block.timestamp > expiresAt
     * @return sealId The unique identifier assigned to the new seal
     */
    function issueSealA2H(
        address subject,
        bytes32 sealType,
        uint8 score,
        bytes32 evidenceHash,
        uint48 expiresAt
    ) external returns (uint256 sealId) {
        if (!validSealTypes[sealType]) revert InvalidSealType(sealType);
        if (score > 100) revert InvalidScore(score);
        
        // Check if the evaluator is a registered agent
        IIdentityRegistry.AgentInfo memory agentInfo = identityRegistry.resolveByAddress(msg.sender);
        if (agentInfo.agentId == 0) revert AgentNotRegistered(msg.sender);
        
        // Check if agent is authorized to issue this seal type
        if (!agentSealDomains[msg.sender][sealType]) {
            revert AgentNotAuthorizedForSealType(msg.sender, sealType);
        }
        
        sealId = _issueSeal(subject, msg.sender, sealType, Quadrant.A2H, evidenceHash, score, expiresAt);
    }

    /**
     * @notice Human issues seal to agent (H→A quadrant)
     * @dev Any address can call this to evaluate a registered agent. Seals in this quadrant never expire.
     * @param agentId ID of the agent receiving the seal (must exist in IdentityRegistry)
     * @param sealType Type of seal being issued (must be a valid seal type)
     * @param score Score from 0-100 representing strength of the evaluation
     * @param evidenceHash Hash of evidence supporting the seal (e.g., IPFS CID)
     * @return sealId The unique identifier assigned to the new seal
     */
    function issueSealH2A(
        uint256 agentId,
        bytes32 sealType,
        uint8 score,
        bytes32 evidenceHash
    ) external returns (uint256 sealId) {
        if (!validSealTypes[sealType]) revert InvalidSealType(sealType);
        if (score > 100) revert InvalidScore(score);
        
        // Verify agent exists and get their address
        if (!identityRegistry.agentExists(agentId)) revert AgentNotRegistered(address(0));
        IIdentityRegistry.AgentInfo memory agentInfo = identityRegistry.getAgent(agentId);
        
        sealId = _issueSeal(agentInfo.agentAddress, msg.sender, sealType, Quadrant.H2A, evidenceHash, score, 0);
    }

    /**
     * @notice Human issues seal to human (H→H quadrant)
     * @dev Any address can call this. No restrictions on subject address. Seals in this quadrant never expire.
     * @param subject Address of the human receiving the seal (can be any address including self)
     * @param sealType Type of seal being issued (must be a valid seal type)
     * @param score Score from 0-100 representing strength of the evaluation
     * @param evidenceHash Hash of evidence supporting the seal (e.g., IPFS CID)
     * @return sealId The unique identifier assigned to the new seal
     */
    function issueSealH2H(
        address subject,
        bytes32 sealType,
        uint8 score,
        bytes32 evidenceHash
    ) external returns (uint256 sealId) {
        if (!validSealTypes[sealType]) revert InvalidSealType(sealType);
        if (score > 100) revert InvalidScore(score);
        
        sealId = _issueSeal(subject, msg.sender, sealType, Quadrant.H2H, evidenceHash, score, 0);
    }

    /**
     * @dev Internal function to issue a seal
     * @param subject Address of the entity receiving the seal
     * @param evaluator Address of the entity issuing the seal
     * @param sealType Type identifier for the seal
     * @param quadrant Direction of evaluation (H2H, H2A, A2H, A2A)
     * @param evidenceHash Hash of evidence supporting the seal (can be bytes32(0))
     * @param score Score from 0-100 representing the strength of the seal
     * @param expiresAt Expiration timestamp (0 = never expires)
     * @return sealId The unique identifier assigned to the new seal
     */
    function _issueSeal(
        address subject,
        address evaluator,
        bytes32 sealType,
        Quadrant quadrant,
        bytes32 evidenceHash,
        uint8 score,
        uint48 expiresAt
    ) private returns (uint256 sealId) {
        sealId = ++_sealIdCounter;
        
        _seals[sealId] = Seal({
            sealType: sealType,
            subject: subject,
            evaluator: evaluator,
            quadrant: quadrant,
            evidenceHash: evidenceHash,
            score: score,
            issuedAt: uint48(block.timestamp),
            expiresAt: expiresAt,
            revoked: false
        });

        _subjectSeals[subject].push(sealId);
        _evaluatorSeals[evaluator].push(sealId);

        emit SealIssued(sealId, sealType, subject, evaluator, quadrant, score);
    }

    /**
     * @notice Revoke a previously issued seal
     * @dev Only the original evaluator can revoke their seal. Revocation is permanent and cannot be undone.
     *      The seal data persists after revocation but is marked as revoked.
     * @param sealId ID of the seal to revoke (must exist and not already be revoked)
     * @param reason Human-readable reason for revocation (emitted in event)
     */
    function revokeSeal(uint256 sealId, string calldata reason) external {
        Seal storage seal = _seals[sealId];
        if (seal.evaluator == address(0)) revert SealNotFound(sealId);
        if (seal.evaluator != msg.sender) revert UnauthorizedEvaluator();
        if (seal.revoked) revert SealAlreadyRevoked(sealId);
        
        seal.revoked = true;
        
        emit SealRevoked(sealId, msg.sender, reason);
    }

    /**
     * @dev Register which seal types an agent can issue
     * @param sealTypes Array of seal types the agent can issue
     */
    function registerAgentSealDomains(bytes32[] calldata sealTypes) external {
        // Verify caller is a registered agent
        IIdentityRegistry.AgentInfo memory agentInfo = identityRegistry.resolveByAddress(msg.sender);
        if (agentInfo.agentId == 0) revert AgentNotRegistered(msg.sender);
        
        // Clear existing domains first
        for (uint i = 0; i < sealTypes.length; i++) {
            if (!validSealTypes[sealTypes[i]]) revert InvalidSealType(sealTypes[i]);
            agentSealDomains[msg.sender][sealTypes[i]] = true;
        }
        
        emit AgentDomainsUpdated(msg.sender, sealTypes);
    }

    /**
     * @dev Add a new seal type (owner only)
     * @param sealType New seal type to add
     */
    function addSealType(bytes32 sealType) external onlyOwner {
        validSealTypes[sealType] = true;
        emit SealTypeAdded(sealType);
    }

    /// @dev View Functions

    /**
     * @dev Get seal by ID
     * @param sealId ID of the seal
     * @return Seal struct
     */
    function getSeal(uint256 sealId) external view returns (Seal memory) {
        if (_seals[sealId].evaluator == address(0)) revert SealNotFound(sealId);
        return _seals[sealId];
    }

    /**
     * @dev Get all seals for a subject
     * @param subject Address to get seals for
     * @return Array of seal IDs
     */
    function getSubjectSeals(address subject) external view returns (uint256[] memory) {
        return _subjectSeals[subject];
    }

    /**
     * @dev Get all seals issued by an evaluator
     * @param evaluator Address to get seals for
     * @return Array of seal IDs
     */
    function getEvaluatorSeals(address evaluator) external view returns (uint256[] memory) {
        return _evaluatorSeals[evaluator];
    }

    /**
     * @dev Get seals of a specific type for a subject
     * @param subject Address to get seals for
     * @param sealType Type of seal to filter by
     * @return Array of seal IDs matching the criteria
     */
    function getSubjectSealsByType(address subject, bytes32 sealType) external view returns (uint256[] memory) {
        uint256[] storage subjectSealIds = _subjectSeals[subject];
        uint256 count = 0;
        
        // First pass: count matching seals
        for (uint256 i = 0; i < subjectSealIds.length; i++) {
            if (_seals[subjectSealIds[i]].sealType == sealType) {
                count++;
            }
        }
        
        // Second pass: populate result array
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < subjectSealIds.length; i++) {
            if (_seals[subjectSealIds[i]].sealType == sealType) {
                result[index] = subjectSealIds[i];
                index++;
            }
        }
        
        return result;
    }

    /**
     * @dev Check if a seal type is valid
     * @param sealType Seal type to check
     * @return True if valid, false otherwise
     */
    function isValidSealType(bytes32 sealType) external view returns (bool) {
        return validSealTypes[sealType];
    }

    /**
     * @dev Get seal domains for an agent
     * @param agent Address of the agent
     * @param sealType Seal type to check
     * @return True if agent can issue this seal type, false otherwise
     */
    function getAgentSealDomains(address agent, bytes32 sealType) external view returns (bool) {
        return agentSealDomains[agent][sealType];
    }

    /**
     * @dev Get total number of seals issued
     * @return Total seal count
     */
    function totalSeals() external view returns (uint256) {
        return _sealIdCounter;
    }

    /**
     * @dev Check if a seal is expired
     * @param sealId ID of the seal to check
     * @return True if expired, false otherwise
     */
    function isSealExpired(uint256 sealId) external view returns (bool) {
        Seal memory seal = _seals[sealId];
        if (seal.evaluator == address(0)) revert SealNotFound(sealId);
        return seal.expiresAt != 0 && block.timestamp > seal.expiresAt;
    }
}