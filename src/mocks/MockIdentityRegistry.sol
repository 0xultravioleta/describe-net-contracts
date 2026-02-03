// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IIdentityRegistry.sol";

/**
 * @title MockIdentityRegistry
 * @dev Mock implementation of IIdentityRegistry for testing purposes
 */
contract MockIdentityRegistry is IIdentityRegistry {
    mapping(uint256 => AgentInfo) private _agents;
    mapping(address => AgentInfo) private _agentsByAddress;

    /**
     * @dev Adds an agent to the mock registry (test helper)
     * @param agentId Unique identifier for the agent
     * @param agentDomain Domain or namespace for the agent
     * @param agentAddress Ethereum address associated with the agent
     */
    function addAgent(uint256 agentId, string calldata agentDomain, address agentAddress) external {
        AgentInfo memory agent = AgentInfo({
            agentId: agentId,
            agentDomain: agentDomain,
            agentAddress: agentAddress
        });
        
        _agents[agentId] = agent;
        _agentsByAddress[agentAddress] = agent;
    }

    /**
     * @dev Returns agent information by agent ID
     * @param agentId The unique identifier of the agent
     * @return AgentInfo struct containing agent details
     */
    function getAgent(uint256 agentId) external view returns (AgentInfo memory) {
        return _agents[agentId];
    }

    /**
     * @dev Resolves agent information by Ethereum address
     * @param addr The Ethereum address to resolve
     * @return AgentInfo struct containing agent details
     */
    function resolveByAddress(address addr) external view returns (AgentInfo memory) {
        return _agentsByAddress[addr];
    }

    /**
     * @dev Checks if an agent exists by agent ID
     * @param agentId The unique identifier to check
     * @return bool True if agent exists, false otherwise
     */
    function agentExists(uint256 agentId) external view returns (bool) {
        return _agents[agentId].agentId != 0;
    }
}