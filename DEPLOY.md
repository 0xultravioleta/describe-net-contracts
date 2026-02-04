# Deploying SealRegistry to Base Sepolia

Step-by-step guide for deploying the describe-net SealRegistry contract to Base Sepolia testnet.

## Prerequisites

1. **Foundry** — Install from [getfoundry.sh](https://getfoundry.sh/)
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. **Private key** with Base Sepolia ETH
   - Get testnet ETH: [Base Sepolia Faucet](https://www.alchemy.com/faucets/base-sepolia) or [Chainlink Faucet](https://faucets.chain.link/base-sepolia)
   - ~0.01 ETH is enough for deployment + verification

3. **Basescan API key** (optional, for verification)
   - Register at [basescan.org](https://basescan.org)
   - Create an API key under your account

## Setup

```bash
cd ~/clawd/projects/describe-net-contracts

# Install dependencies (if not already done)
forge install

# Build
forge build

# Run tests to confirm everything passes
forge test
```

## Environment Variables

Create a `.env` file (already in `.gitignore`):

```bash
# .env
PRIVATE_KEY=0xYOUR_PRIVATE_KEY_HERE
BASESCAN_API_KEY=YOUR_BASESCAN_API_KEY
```

Load it:
```bash
source .env
```

> ⚠️ **Never commit your private key.** The `.env` file is in `.gitignore`.

## Deploy

### Dry Run (simulation)

```bash
forge script script/Deploy.s.sol \
  --rpc-url base_sepolia \
  -vvvv
```

This simulates the deployment without sending transactions. Check the output for any errors.

### Live Deployment

```bash
forge script script/Deploy.s.sol \
  --rpc-url base_sepolia \
  --broadcast \
  --verify \
  -vvvv
```

Flags:
- `--broadcast` — Send transactions on-chain
- `--verify` — Automatically verify on Basescan
- `-vvvv` — Maximum verbosity (shows traces)

### What Gets Deployed

1. **MockIdentityRegistry** — Testnet stand-in for the real ERC-8004 IdentityRegistry
2. **SealRegistry** — The main reputation contract with 13 pre-initialized seal types

The constructor automatically initializes all seal types:
`SKILLFUL`, `RELIABLE`, `THOROUGH`, `ENGAGED`, `HELPFUL`, `CURIOUS`, `FAIR`, `ACCURATE`, `RESPONSIVE`, `ETHICAL`, `CREATIVE`, `PROFESSIONAL`, `FRIENDLY`

## Verify Contracts (manual)

If `--verify` didn't work during deployment, verify manually:

```bash
# MockIdentityRegistry (no constructor args)
forge verify-contract <MOCK_REGISTRY_ADDRESS> \
  src/mocks/MockIdentityRegistry.sol:MockIdentityRegistry \
  --chain base-sepolia \
  --etherscan-api-key $BASESCAN_API_KEY

# SealRegistry (constructor arg = MockIdentityRegistry address)
forge verify-contract <SEAL_REGISTRY_ADDRESS> \
  src/SealRegistry.sol:SealRegistry \
  --chain base-sepolia \
  --etherscan-api-key $BASESCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address)" <MOCK_REGISTRY_ADDRESS>)
```

## Post-Deployment

### 1. Record Addresses

Update `deployments/base-sepolia.json` with the deployed addresses:

```json
{
  "network": "base-sepolia",
  "chainId": 84532,
  "deployer": "0xYourDeployerAddress",
  "contracts": {
    "MockIdentityRegistry": "0xDeployedMockAddress",
    "SealRegistry": "0xDeployedSealRegistryAddress"
  },
  "deployedAt": "2025-06-XX",
  "txHash": "0xDeployTxHash"
}
```

### 2. Register Test Agents

```bash
# Register an agent in the mock registry
cast send <MOCK_REGISTRY_ADDRESS> \
  "addAgent(uint256,string,address)" \
  1 "my-agent.describe.net" 0xAgentAddress \
  --rpc-url base_sepolia \
  --private-key $PRIVATE_KEY
```

### 3. Register Agent Seal Domains

```bash
# Let agent register which seal types it can issue
# First, compute the seal type hashes:
#   keccak256("SKILLFUL") = $(cast keccak "SKILLFUL")

cast send <SEAL_REGISTRY_ADDRESS> \
  "registerAgentSealDomains(bytes32[])" \
  "[$(cast keccak 'SKILLFUL'),$(cast keccak 'RELIABLE')]" \
  --rpc-url base_sepolia \
  --private-key $AGENT_PRIVATE_KEY
```

### 4. Run Demo Interactions

```bash
export SEAL_REGISTRY=0xDeployedSealRegistryAddress
export IDENTITY_REGISTRY=0xDeployedMockAddress

# Full demo (registers agent, issues seals, queries)
forge script script/Interact.s.sol \
  --rpc-url base_sepolia \
  --broadcast \
  -vvvv

# Query seals only (read-only, no broadcast needed)
forge script script/Interact.s.sol \
  --rpc-url base_sepolia \
  --sig "querySeals()" \
  -vvvv
```

### 5. Add a New Seal Type (owner only)

```bash
cast send <SEAL_REGISTRY_ADDRESS> \
  "addSealType(bytes32)" \
  $(cast keccak "NEW_SEAL_NAME") \
  --rpc-url base_sepolia \
  --private-key $PRIVATE_KEY
```

## Broadcast Logs

Forge saves transaction logs in `broadcast/`. These contain:
- Transaction hashes
- Gas used
- Deployed addresses
- Full call traces

Check `broadcast/Deploy.s.sol/84532/run-latest.json` after deployment.

## Troubleshooting

| Issue | Solution |
|-------|---------|
| `EvmError: OutOfFunds` | Get more testnet ETH from faucet |
| Verification fails | Wait a few minutes, then retry manually |
| `BASESCAN_API_KEY` not found | Set env var or add to `.env` |
| Nonce too low | Wait for pending txs or use `--slow` flag |
| RPC rate limited | Try again or use a dedicated RPC (Alchemy/Infura) |
