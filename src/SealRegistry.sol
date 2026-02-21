// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./interfaces/IIdentityRegistry.sol";

/**
 * @title SealRegistry
 * @dev Categorical reputation system for the describe.net protocol
 * @dev describe-net is a universal reputation protocol where humans and agents evaluate each other
 * It extends the ERC-8004 agent identity standard with categorical "seals" (like SKILLFUL, RELIABLE, FAIR, etc.)
 * The SealRegistry sits alongside the existing IdentityRegistry and ReputationRegistry contracts
 *
 * Features:
 * - Four quadrant evaluation: H2H, H2A, A2H, A2A
 * - Batch seal issuance (up to 50 per TX)
 * - EIP-712 meta-transactions (off-chain signing, on-chain submission)
 * - Delegation system (agents can authorize sub-agents to issue seals)
 * - Composite scoring with time-weighted decay
 */
contract SealRegistry is Ownable, EIP712 {
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

    /// @dev EIP-712 typehash for meta-transaction seal submission
    bytes32 public constant SEAL_TYPEHASH = keccak256(
        "Seal(address subject,bytes32 sealType,uint8 quadrant,uint8 score,bytes32 evidenceHash,uint48 expiresAt,uint256 nonce,uint256 deadline)"
    );

    /**
     * @dev Structure representing a delegation of seal-issuing authority
     * @param delegator The agent who granted the delegation
     * @param expiresAt When the delegation expires (0 = never)
     * @param revoked Whether the delegation has been revoked
     * @param sealTypeCount Number of seal types authorized
     */
    struct Delegation {
        address delegator;
        uint48 expiresAt;
        bool revoked;
    }

    /// @dev Counter for seal IDs
    uint256 private _sealIdCounter;

    /// @dev Identity registry interface
    IIdentityRegistry public identityRegistry;

    /// @dev Nonce per evaluator for EIP-712 meta-transactions (replay protection)
    mapping(address => uint256) public nonces;

    /// @dev Delegation: delegator => delegate => Delegation
    mapping(address => mapping(address => Delegation)) private _delegations;

    /// @dev Delegation seal type authorization: delegator => delegate => sealType => authorized
    mapping(address => mapping(address => mapping(bytes32 => bool))) private _delegatedSealTypes;

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

    event DelegationGranted(
        address indexed delegator,
        address indexed delegate,
        bytes32[] sealTypes,
        uint48 expiresAt
    );

    event DelegationRevoked(address indexed delegator, address indexed delegate);

    event SealIssuedByDelegate(
        uint256 indexed sealId,
        address indexed delegator,
        address indexed delegate
    );

    event MetaTxSealSubmitted(
        uint256 indexed sealId,
        address indexed evaluator,
        address indexed relayer
    );

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
    
    /// @notice Thrown when an entity attempts to evaluate itself
    error SelfFeedbackNotAllowed();
    
    /// @notice Thrown when batch arrays have mismatched lengths
    error BatchLengthMismatch();
    
    /// @notice Thrown when batch size is 0 or exceeds maximum (50)
    /// @param size The invalid batch size
    error BatchSizeInvalid(uint256 size);
    
    /// @notice Thrown when a delegation does not exist or has been revoked
    error DelegationNotActive();
    
    /// @notice Thrown when a delegate tries to issue a seal type not in their delegation
    error DelegateNotAuthorizedForSealType(address delegate, bytes32 sealType);
    
    /// @notice Thrown when an agent tries to delegate to themselves
    error SelfDelegationNotAllowed();
    
    /// @notice Thrown when a meta-transaction signature is invalid
    error InvalidSignature();
    
    /// @notice Thrown when a meta-transaction deadline has passed
    error DeadlineExpired();
    
    /// @notice Thrown when a meta-transaction nonce doesn't match
    error InvalidNonce();

    /**
     * @dev Constructor
     * @param _identityRegistry Address of the identity registry contract
     */
    constructor(address _identityRegistry) Ownable(msg.sender) EIP712("SealRegistry", "2") {
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
     * @notice Agent issues seal to agent (A→A quadrant)
     * @dev Both evaluator and subject must be registered agents. Evaluator must have the sealType in their domains.
     *      This enables agent-to-agent reputation in multi-agent systems (e.g., KarmaCadabra swarms).
     * @param subjectAgentId ID of the agent receiving the seal (must exist in IdentityRegistry)
     * @param sealType Type of seal being issued (must be a valid seal type)
     * @param score Score from 0-100 representing strength of the evaluation
     * @param evidenceHash Hash of evidence supporting the seal (e.g., task completion hash, IPFS CID)
     * @param expiresAt Expiration timestamp (0 for never expires)
     * @return sealId The unique identifier assigned to the new seal
     */
    function issueSealA2A(
        uint256 subjectAgentId,
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
        
        // Verify subject agent exists
        if (!identityRegistry.agentExists(subjectAgentId)) revert AgentNotRegistered(address(0));
        IIdentityRegistry.AgentInfo memory subjectInfo = identityRegistry.getAgent(subjectAgentId);
        
        // Prevent self-evaluation
        if (msg.sender == subjectInfo.agentAddress) revert SelfFeedbackNotAllowed();
        
        sealId = _issueSeal(subjectInfo.agentAddress, msg.sender, sealType, Quadrant.A2A, evidenceHash, score, expiresAt);
    }

    /**
     * @dev Packed parameters for a single seal in a batch operation
     */
    struct BatchSealParams {
        address subject;
        bytes32 sealType;
        Quadrant quadrant;
        uint8 score;
        bytes32 evidenceHash;
        uint48 expiresAt;
    }

    /**
     * @notice Batch issue seals (any quadrant, same evaluator)
     * @dev Issues multiple seals in a single transaction. All seals are from msg.sender.
     *      Useful for end-of-task evaluations where multiple dimensions are assessed at once.
     *      Agent identity is checked only once per batch (gas optimization).
     * @param sealParams Array of packed seal parameters
     * @return sealIds Array of created seal IDs
     */
    function batchIssueSeal(
        BatchSealParams[] calldata sealParams
    ) external returns (uint256[] memory sealIds) {
        uint256 len = sealParams.length;
        if (len == 0 || len > 50) revert BatchSizeInvalid(len);
        
        sealIds = new uint256[](len);
        
        // Cache agent check — only look up once if any seal requires agent auth
        bool agentChecked = false;
        bool isAgent = false;
        
        for (uint256 i = 0; i < len; i++) {
            BatchSealParams calldata p = sealParams[i];
            if (!validSealTypes[p.sealType]) revert InvalidSealType(p.sealType);
            if (p.score > 100) revert InvalidScore(p.score);
            
            // For agent quadrants (A2H, A2A), verify evaluator is registered agent with domain
            if (p.quadrant == Quadrant.A2H || p.quadrant == Quadrant.A2A) {
                if (!agentChecked) {
                    IIdentityRegistry.AgentInfo memory agentInfo = identityRegistry.resolveByAddress(msg.sender);
                    isAgent = agentInfo.agentId != 0;
                    agentChecked = true;
                }
                if (!isAgent) revert AgentNotRegistered(msg.sender);
                if (!agentSealDomains[msg.sender][p.sealType]) {
                    revert AgentNotAuthorizedForSealType(msg.sender, p.sealType);
                }
            }
            
            sealIds[i] = _issueSeal(
                p.subject, msg.sender, p.sealType, p.quadrant,
                p.evidenceHash, p.score, p.expiresAt
            );
        }
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

    /**
     * @notice Calculate composite reputation score for a subject
     * @dev Returns the average score across all active (non-revoked, non-expired) seals.
     *      Optionally filter by quadrant. Returns 0 if no active seals found.
     * @param subject Address to calculate score for
     * @param filterQuadrant If true, only count seals from the specified quadrant
     * @param quadrant Quadrant to filter by (only used if filterQuadrant is true)
     * @return averageScore The weighted average score (0-100)
     * @return activeCount Number of active seals counted
     * @return totalCount Total number of seals (including expired/revoked)
     */
    function compositeScore(
        address subject,
        bool filterQuadrant,
        Quadrant quadrant
    ) external view returns (uint256 averageScore, uint256 activeCount, uint256 totalCount) {
        uint256[] storage sealIds = _subjectSeals[subject];
        totalCount = sealIds.length;
        
        uint256 scoreSum = 0;
        
        for (uint256 i = 0; i < sealIds.length; i++) {
            Seal memory seal = _seals[sealIds[i]];
            
            // Skip revoked seals
            if (seal.revoked) continue;
            
            // Skip expired seals
            if (seal.expiresAt != 0 && block.timestamp > seal.expiresAt) continue;
            
            // Apply quadrant filter if requested
            if (filterQuadrant && seal.quadrant != quadrant) continue;
            
            scoreSum += seal.score;
            activeCount++;
        }
        
        if (activeCount > 0) {
            averageScore = scoreSum / activeCount;
        }
    }

    /**
     * @notice Get reputation breakdown by seal type for a subject
     * @dev Returns the average score for a specific seal type across all active seals
     * @param subject Address to check
     * @param sealType Seal type to aggregate
     * @return averageScore Average score for this seal type
     * @return count Number of active seals of this type
     */
    function reputationByType(
        address subject,
        bytes32 sealType
    ) external view returns (uint256 averageScore, uint256 count) {
        uint256[] storage sealIds = _subjectSeals[subject];
        uint256 scoreSum = 0;
        
        for (uint256 i = 0; i < sealIds.length; i++) {
            Seal memory seal = _seals[sealIds[i]];
            
            if (seal.sealType != sealType) continue;
            if (seal.revoked) continue;
            if (seal.expiresAt != 0 && block.timestamp > seal.expiresAt) continue;
            
            scoreSum += seal.score;
            count++;
        }
        
        if (count > 0) {
            averageScore = scoreSum / count;
        }
    }

    /**
     * @notice Get seals filtered by quadrant for a subject
     * @param subject Address to get seals for
     * @param quadrant Quadrant to filter by
     * @return Array of seal IDs in the specified quadrant
     */
    function getSubjectSealsByQuadrant(
        address subject,
        Quadrant quadrant
    ) external view returns (uint256[] memory) {
        uint256[] storage subjectSealIds = _subjectSeals[subject];
        uint256 count = 0;
        
        for (uint256 i = 0; i < subjectSealIds.length; i++) {
            if (_seals[subjectSealIds[i]].quadrant == quadrant) {
                count++;
            }
        }
        
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < subjectSealIds.length; i++) {
            if (_seals[subjectSealIds[i]].quadrant == quadrant) {
                result[index] = subjectSealIds[i];
                index++;
            }
        }
        
        return result;
    }

    // ============================================================
    //                    DELEGATION SYSTEM
    // ============================================================

    /**
     * @notice Grant seal-issuing authority to a delegate agent
     * @dev Only registered agents can delegate. The delegate need not be a registered agent —
     *      this enables temporary sub-agents (e.g., in KC swarms) to issue seals on behalf
     *      of their parent agent's identity. The seal's evaluator is recorded as the delegate,
     *      with the delegation relationship tracked via events.
     * @param delegate Address of the agent being granted authority
     * @param sealTypes Array of seal types the delegate can issue
     * @param expiresAt When the delegation expires (0 = never)
     */
    function delegateSealAuthority(
        address delegate,
        bytes32[] calldata sealTypes,
        uint48 expiresAt
    ) external {
        if (delegate == msg.sender) revert SelfDelegationNotAllowed();
        
        // Verify delegator is a registered agent
        IIdentityRegistry.AgentInfo memory agentInfo = identityRegistry.resolveByAddress(msg.sender);
        if (agentInfo.agentId == 0) revert AgentNotRegistered(msg.sender);
        
        // Verify all seal types are valid and delegator has them in their domains
        for (uint256 i = 0; i < sealTypes.length; i++) {
            if (!validSealTypes[sealTypes[i]]) revert InvalidSealType(sealTypes[i]);
            if (!agentSealDomains[msg.sender][sealTypes[i]]) {
                revert AgentNotAuthorizedForSealType(msg.sender, sealTypes[i]);
            }
            _delegatedSealTypes[msg.sender][delegate][sealTypes[i]] = true;
        }
        
        _delegations[msg.sender][delegate] = Delegation({
            delegator: msg.sender,
            expiresAt: expiresAt,
            revoked: false
        });
        
        emit DelegationGranted(msg.sender, delegate, sealTypes, expiresAt);
    }

    /**
     * @notice Revoke a previously granted delegation
     * @dev Only the original delegator can revoke. Revocation is permanent for this delegation.
     * @param delegate Address of the delegate to revoke
     */
    function revokeDelegation(address delegate) external {
        Delegation storage del = _delegations[msg.sender][delegate];
        if (del.delegator == address(0)) revert DelegationNotActive();
        
        del.revoked = true;
        
        emit DelegationRevoked(msg.sender, delegate);
    }

    /**
     * @notice Issue a seal as a delegate on behalf of a delegator
     * @dev The delegate must have an active, non-expired delegation from the delegator
     *      that includes the specified seal type. The seal is issued with the delegate
     *      as evaluator (transparent delegation chain via events).
     * @param delegator Address of the agent who granted the delegation
     * @param subject Address of the entity receiving the seal
     * @param sealType Type of seal being issued
     * @param quadrant Direction of evaluation
     * @param score Score from 0-100
     * @param evidenceHash Hash of evidence supporting the seal
     * @param expiresAt Expiration timestamp for the seal (0 = never)
     * @return sealId The unique identifier assigned to the new seal
     */
    function issueSealAsDelegate(
        address delegator,
        address subject,
        bytes32 sealType,
        Quadrant quadrant,
        uint8 score,
        bytes32 evidenceHash,
        uint48 expiresAt
    ) external returns (uint256 sealId) {
        if (!validSealTypes[sealType]) revert InvalidSealType(sealType);
        if (score > 100) revert InvalidScore(score);
        
        // Verify delegation is active
        Delegation memory del = _delegations[delegator][msg.sender];
        if (del.delegator == address(0) || del.revoked) revert DelegationNotActive();
        if (del.expiresAt != 0 && block.timestamp > del.expiresAt) revert DelegationNotActive();
        
        // Verify delegate is authorized for this seal type
        if (!_delegatedSealTypes[delegator][msg.sender][sealType]) {
            revert DelegateNotAuthorizedForSealType(msg.sender, sealType);
        }
        
        // Issue seal with delegate as evaluator (transparent chain)
        sealId = _issueSeal(subject, msg.sender, sealType, quadrant, evidenceHash, score, expiresAt);
        
        emit SealIssuedByDelegate(sealId, delegator, msg.sender);
    }

    /**
     * @notice Check if a delegation is currently active
     * @param delegator Address of the delegator
     * @param delegate Address of the delegate
     * @return active True if delegation exists, is not revoked, and has not expired
     */
    function isDelegationActive(address delegator, address delegate) external view returns (bool active) {
        Delegation memory del = _delegations[delegator][delegate];
        if (del.delegator == address(0) || del.revoked) return false;
        if (del.expiresAt != 0 && block.timestamp > del.expiresAt) return false;
        return true;
    }

    /**
     * @notice Check if a delegate is authorized for a specific seal type
     * @param delegator Address of the delegator
     * @param delegate Address of the delegate
     * @param sealType Seal type to check
     * @return True if delegate can issue this seal type on behalf of delegator
     */
    function isDelegateAuthorizedForType(
        address delegator,
        address delegate,
        bytes32 sealType
    ) external view returns (bool) {
        return _delegatedSealTypes[delegator][delegate][sealType];
    }

    // ============================================================
    //              EIP-712 META-TRANSACTION SEALS
    // ============================================================

    /**
     * @dev Packed parameters for meta-transaction seal submission (avoids stack-too-deep)
     */
    struct MetaTxParams {
        address subject;
        bytes32 sealType;
        uint8 quadrant;
        uint8 score;
        bytes32 evidenceHash;
        uint48 expiresAt;
        uint256 nonce;
        uint256 deadline;
    }

    /**
     * @notice Submit a seal signed off-chain by the evaluator (meta-transaction)
     * @dev Enables gasless seal issuance for agents. The evaluator signs the seal data
     *      off-chain using EIP-712, and any relayer can submit it on-chain.
     *      This is critical for swarm operations where 8+ agents issue seals simultaneously.
     *      The relayer pays gas; the evaluator's nonce is incremented to prevent replay.
     * @param params Packed seal parameters
     * @param signature EIP-712 signature from the evaluator
     * @return sealId The unique identifier assigned to the new seal
     */
    function submitSealWithSignature(
        MetaTxParams calldata params,
        bytes calldata signature
    ) external returns (uint256 sealId) {
        if (block.timestamp > params.deadline) revert DeadlineExpired();
        if (!validSealTypes[params.sealType]) revert InvalidSealType(params.sealType);
        if (params.score > 100) revert InvalidScore(params.score);
        if (params.quadrant > 3) revert InvalidSealType(params.sealType);
        
        // Recover evaluator from EIP-712 signature
        address evaluator = _recoverMetaTxSigner(params, signature);
        
        // Verify nonce
        if (nonces[evaluator] != params.nonce) revert InvalidNonce();
        nonces[evaluator]++;
        
        // Validate agent permissions for agent quadrants
        Quadrant q = Quadrant(params.quadrant);
        _validateMetaTxAgent(evaluator, params.sealType, params.subject, q);
        
        sealId = _issueSeal(params.subject, evaluator, params.sealType, q, params.evidenceHash, params.score, params.expiresAt);
        
        emit MetaTxSealSubmitted(sealId, evaluator, msg.sender);
    }

    /**
     * @dev Recover signer from EIP-712 meta-transaction signature
     */
    function _recoverMetaTxSigner(
        MetaTxParams calldata params,
        bytes calldata signature
    ) private view returns (address) {
        bytes32 structHash = keccak256(abi.encode(
            SEAL_TYPEHASH,
            params.subject,
            params.sealType,
            params.quadrant,
            params.score,
            params.evidenceHash,
            params.expiresAt,
            params.nonce,
            params.deadline
        ));
        
        return ECDSA.recover(_hashTypedDataV4(structHash), signature);
    }

    /**
     * @dev Validate agent permissions for meta-transaction seals
     */
    function _validateMetaTxAgent(
        address evaluator,
        bytes32 sealType,
        address subject,
        Quadrant q
    ) private view {
        if (q == Quadrant.A2H || q == Quadrant.A2A) {
            IIdentityRegistry.AgentInfo memory agentInfo = identityRegistry.resolveByAddress(evaluator);
            if (agentInfo.agentId == 0) revert AgentNotRegistered(evaluator);
            if (!agentSealDomains[evaluator][sealType]) {
                revert AgentNotAuthorizedForSealType(evaluator, sealType);
            }
        }
        if (q == Quadrant.A2A && evaluator == subject) revert SelfFeedbackNotAllowed();
    }

    /**
     * @notice Batch submit seals with signatures (multi-evaluator meta-transactions)
     * @dev Submit up to 20 signed seals in one transaction. Each seal can be from a different
     *      evaluator. Designed for swarm completion events where multiple agents evaluate each other.
     * @param params Array of packed seal parameters
     * @param signatures Array of EIP-712 signatures (one per params entry)
     * @return sealIds Array of created seal IDs
     */
    function batchSubmitSealsWithSignatures(
        MetaTxParams[] calldata params,
        bytes[] calldata signatures
    ) external returns (uint256[] memory sealIds) {
        uint256 len = params.length;
        if (len != signatures.length) revert BatchLengthMismatch();
        if (len == 0 || len > 20) revert BatchSizeInvalid(len);
        
        sealIds = new uint256[](len);
        
        for (uint256 i = 0; i < len; i++) {
            sealIds[i] = this.submitSealWithSignature(params[i], signatures[i]);
        }
    }

    /**
     * @notice Get the EIP-712 domain separator
     * @dev Useful for off-chain signature construction
     * @return The domain separator hash
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ============================================================
    //              TIME-WEIGHTED SCORING
    // ============================================================

    /**
     * @notice Calculate time-weighted composite score with exponential decay
     * @dev More recent seals carry more weight. Uses a half-life model where a seal's
     *      weight halves every `halfLifeSeconds`. This incentivizes consistent performance.
     *      Weight formula: weight = 2^(-age/halfLife) approximated as (halfLife / (halfLife + age))
     *      Using hyperbolic approximation to avoid floating point: w = halfLife / (halfLife + age)
     * @param subject Address to calculate score for
     * @param halfLifeSeconds Half-life in seconds (e.g., 30 days = 2592000)
     * @param filterQuadrant If true, only count seals from the specified quadrant
     * @param quadrant Quadrant to filter by (only used if filterQuadrant is true)
     * @return weightedScore The time-weighted average score (0-100, scaled by 100 for precision)
     * @return activeCount Number of active seals counted
     */
    function timeWeightedScore(
        address subject,
        uint256 halfLifeSeconds,
        bool filterQuadrant,
        Quadrant quadrant
    ) external view returns (uint256 weightedScore, uint256 activeCount) {
        require(halfLifeSeconds > 0, "Half-life must be positive");
        
        uint256[] storage sealIds = _subjectSeals[subject];
        uint256 weightedSum = 0;
        uint256 totalWeight = 0;
        
        for (uint256 i = 0; i < sealIds.length; i++) {
            Seal memory seal = _seals[sealIds[i]];
            
            if (seal.revoked) continue;
            if (seal.expiresAt != 0 && block.timestamp > seal.expiresAt) continue;
            if (filterQuadrant && seal.quadrant != quadrant) continue;
            
            // Hyperbolic decay: weight = halfLife / (halfLife + age)
            // Multiply by 1e18 for precision
            uint256 age = block.timestamp - seal.issuedAt;
            uint256 weight = (halfLifeSeconds * 1e18) / (halfLifeSeconds + age);
            
            weightedSum += uint256(seal.score) * weight;
            totalWeight += weight;
            activeCount++;
        }
        
        if (totalWeight > 0) {
            weightedScore = weightedSum / totalWeight;
        }
    }
}