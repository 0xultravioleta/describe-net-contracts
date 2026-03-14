// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IIdentityRegistry
 * @dev Interface for the existing ERC-8004 IdentityRegistry contract
 * @dev describe-net is a universal reputation protocol where humans and agents evaluate each other
 * This interface allows interaction with agent identities in the system
 */
interface IIdentityRegistry {
    /**
     * @dev Struct containing agent information
     * @param agentId Unique identifier for the agent
     * @param agentDomain Domain or namespace for the agent
     * @param agentAddress Ethereum address associated with the agent
     */
    struct AgentInfo {
        uint256 agentId;
        string agentDomain;
        address agentAddress;
    }

    /**
     * @dev Returns agent information by agent ID
     * @param agentId The unique identifier of the agent
     * @return AgentInfo struct containing agent details
     */
    function getAgent(uint256 agentId) external view returns (AgentInfo memory);

    /**
     * @dev Resolves agent information by Ethereum address
     * @param addr The Ethereum address to resolve
     * @return AgentInfo struct containing agent details
     */
    function resolveByAddress(address addr) external view returns (AgentInfo memory);

    /**
     * @dev Checks if an agent exists by agent ID
     * @param agentId The unique identifier to check
     * @return bool True if agent exists, false otherwise
     */
    function agentExists(uint256 agentId) external view returns (bool);
}
