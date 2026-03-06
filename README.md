# SealRegistry - describe-net Categorical Reputation System

## Overview

**describe-net** is a universal reputation protocol where humans and agents evaluate each other through categorical "seals" - specific reputation markers like SKILLFUL, RELIABLE, FAIR, etc.

The **SealRegistry** contract is a core component of the describe-net ecosystem that:
- Extends the ERC-8004 agent identity standard with categorical reputation seals
- Enables bidirectional evaluation between humans and AI agents
- Provides granular, domain-specific reputation tracking
- Sits alongside the existing IdentityRegistry and ReputationRegistry contracts

## Architecture

### Core Components

- **SealRegistry.sol** - Main contract for issuing, managing, and querying seals
- **IIdentityRegistry.sol** - Interface to the ERC-8004 agent identity system
- **MockIdentityRegistry.sol** - Mock implementation for testing

### Evaluation Quadrants

The system supports four types of evaluations:
- **H2H** (Human → Human) - Traditional peer-to-peer reputation
- **H2A** (Human → Agent) - Human feedback on AI agent performance  
- **A2H** (Agent → Human) - AI agent evaluation of human interactions
- **A2A** (Agent → Agent) - Inter-agent reputation exchange

### Initial Seal Types

**Agent → Human (A2H)**
- SKILLFUL - Technical competency and expertise
- RELIABLE - Consistent performance and dependability
- THOROUGH - Attention to detail and completeness
- ENGAGED - Active participation and involvement
- HELPFUL - Willingness to assist and support
- CURIOUS - Inquisitiveness and learning orientation

**Human → Agent (H2A)**
- FAIR - Unbiased and equitable treatment
- ACCURATE - Correctness and precision
- RESPONSIVE - Timely and relevant communication
- ETHICAL - Adherence to moral principles

**Human → Human (H2H)**
- CREATIVE - Innovation and original thinking
- PROFESSIONAL - Business acumen and conduct
- FRIENDLY - Positive interpersonal interactions

### EIP-712 Meta-Transaction Seal Issuer Pipeline

The protocol now supports a complete off-chain-to-on-chain reputation flywheel through the **Seal Issuer** pipeline. This allows gasless seal issuance for AI agents and batching of reputation data.

Key features of the pipeline:
- **EIP-712 Meta-Transactions:** Agents sign seal data off-chain using EIP-712 typed data signatures. A relayer can then submit these signatures to the `SealRegistry` on Base, paying the gas on behalf of the agent.
- **Batch Submission:** Up to 20 seals can be submitted in a single transaction via `batchSubmitSealsWithSignatures`, significantly reducing gas overhead for high-throughput AI swarms.
- **Bidirectional Reputation Mapping:** The system maps real-world task completions to on-chain reputation. Specifically, it maps **11 Execution Market task categories** directly into the **13 describe-net seal types**, covering A2H (agent evaluating human), H2A (human evaluating agent), and A2A (inter-agent swarm coordination) quadrants.

For a complete reference implementation of the issuer pipeline in Python, see `~/clawd/projects/karmakadabra/lib/seal_issuer.py` in the Karma Kadabra V2 repository.

## Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/) installed
- Node.js and npm/yarn (optional, for additional tooling)

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd describe-net-contracts

# Install dependencies
forge install

# Build the project
forge build

# Run tests
forge test

# Run tests with verbosity
forge test -vvv
```

### Configuration

The project is configured for Base Sepolia testnet. Update `foundry.toml` for other networks:

```toml
[rpc_endpoints]
mainnet = "YOUR_MAINNET_RPC"
polygon = "YOUR_POLYGON_RPC"
```

## Usage

### Deploying Contracts

```bash
# Set environment variables
export PRIVATE_KEY="your-private-key"

# Deploy to Base Sepolia
forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify
```

### Interacting with Contracts

#### For Agents

1. **Register Seal Domains** (what seals you can issue):
```solidity
bytes32[] memory sealTypes = new bytes32[](2);
sealTypes[0] = keccak256("SKILLFUL");
sealTypes[1] = keccak256("RELIABLE");
sealRegistry.registerAgentSealDomains(sealTypes);
```

2. **Issue Seals to Humans**:
```solidity
sealRegistry.issueSealA2H(
    humanAddress,
    keccak256("SKILLFUL"),
    85, // score 0-100
    evidenceHash,
    expirationTimestamp // 0 for never expires
);
```

#### For Humans

1. **Evaluate Agents**:
```solidity
sealRegistry.issueSealH2A(
    agentId,
    keccak256("FAIR"),
    90, // score 0-100
    evidenceHash
);
```

2. **Evaluate Other Humans**:
```solidity
sealRegistry.issueSealH2H(
    otherHumanAddress,
    keccak256("CREATIVE"),
    75,
    evidenceHash
);
```

### Querying Reputation

```solidity
// Get all seals for a subject
uint256[] memory seals = sealRegistry.getSubjectSeals(address);

// Get seals of specific type
uint256[] memory skillfulSeals = sealRegistry.getSubjectSealsByType(
    address, 
    keccak256("SKILLFUL")
);

// Get specific seal details
SealRegistry.Seal memory seal = sealRegistry.getSeal(sealId);

// Check if seal is expired
bool isExpired = sealRegistry.isSealExpired(sealId);
```

## Testing

**98 tests passing** across 2 test suites:

### SealRegistry Tests (79 tests)
- ✅ A→H seal issuance (happy path + edge cases)
- ✅ H→A seal issuance (happy path + edge cases)  
- ✅ H→H seal issuance (happy path + edge cases)
- ✅ A→A seal issuance (agent-to-agent evaluation)
- ✅ Seal revocation (only by evaluator)
- ✅ Unauthorized agent seal issuance protection
- ✅ Unregistered address protection
- ✅ Invalid seal type validation
- ✅ Score validation (0-100)
- ✅ Seal expiration detection
- ✅ Subject seal retrieval + filtering by type
- ✅ Admin functions (owner-only)
- ✅ Agent domain registration
- ✅ EIP-712 meta-transactions
- ✅ Delegation system
- ✅ Time-weighted reputation scoring
- ✅ Batch operations (mint + seal)
- ✅ Composite scoring across quadrants

### ERC-8004 Reputation Adapter Tests (19 tests)
- ✅ Adapter registration and interface compliance
- ✅ Score normalization from seal data
- ✅ Quadrant-specific queries

```bash
# Run all tests
forge test

# Run specific test
forge test --match-test testIssueSealA2H_HappyPath

# Run with gas reporting
forge test --gas-report
```

## Contract Addresses

### Monad Testnet (Live)
- **SealRegistry:** `0xAb06ADC19cb16728bd53755B412BadeE73335D10`
- **MockIdentityRegistry:** `0xdF93dA72C2B58A8436C5bA7cC6DDc9101D680D96`
- Chain ID: 10143 | RPC: `https://testnet-rpc.monad.xyz`

### Base Sepolia (Pending Deployment)
- *Awaiting testnet ETH funding*

### Base Mainnet (Target)
- Will deploy alongside ERC-8004 IdentityRegistry (`0x8004A169FB4a3325136EB29fA0ceB6D2e539a432`) and ReputationRegistry (`0x8004BAa17C55a88189AE136b182e5fdA19dE9b63`)

## Gas Optimization

The contracts are optimized for gas efficiency:
- Packed structs for storage efficiency
- Efficient mapping structures
- Minimal external calls
- Optimized loops in view functions

## Security Considerations

- **Access Control**: Only registered agents can issue A2H seals
- **Domain Restriction**: Agents must register seal types they can issue
- **Revocation Rights**: Only seal issuers can revoke their seals
- **Input Validation**: Score limits, seal type validation, expiration checks
- **Reentrancy Protection**: No external calls in state-changing functions

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Links

- [describe-net Protocol](https://describe.net)
- [ERC-8004 Specification](https://eips.ethereum.org/EIPS/eip-8004)
- [Foundry Documentation](https://book.getfoundry.sh/)
- [OpenZeppelin Contracts](https://openzeppelin.com/contracts/)