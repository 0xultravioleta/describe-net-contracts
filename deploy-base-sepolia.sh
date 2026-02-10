#!/bin/bash

# Base Sepolia Deployment Script for describe-net
# Run this script once you have Base Sepolia testnet ETH
# Usage: ./deploy-base-sepolia.sh

set -e  # Exit on any error

echo "🚀 describe-net Base Sepolia Deployment"
echo "======================================="

# Configuration
NETWORK="base-sepolia"
CHAIN_ID="84532"
RPC_URL="https://sepolia.base.org"
DEPLOYER_ADDRESS="0xD3868E1eD738CED6945A574a7c769433BeD5d474"

# Get private key from AWS
echo "🔐 Retrieving private key from AWS..."
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id em/x402 --region us-east-2 --query SecretString --output text 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "❌ Error: Could not retrieve private key from AWS"
    echo "   Make sure AWS CLI is configured and you have access to em/x402"
    exit 1
fi

# Extract private key
PRIVATE_KEY=$(echo $SECRET_JSON | jq -r '.PRIVATE_KEY')
if [ "$PRIVATE_KEY" = "null" ] || [ -z "$PRIVATE_KEY" ]; then
    echo "❌ Error: Could not extract PRIVATE_KEY from AWS secret"
    exit 1
fi

# Check if we have Base Sepolia ETH
echo "💰 Checking wallet balance..."
BALANCE=$(cast balance $DEPLOYER_ADDRESS --rpc-url $RPC_URL)
echo "   Balance: $BALANCE wei"

# Convert to ETH for readability
BALANCE_ETH=$(cast to-unit $BALANCE ether 2>/dev/null || echo "0")
echo "   Balance: $BALANCE_ETH ETH"

# Check if we have enough ETH (need at least 0.001 ETH)
MIN_BALANCE="1000000000000000"  # 0.001 ETH in wei
if [ "$BALANCE" -lt "$MIN_BALANCE" ]; then
    echo "❌ Error: Insufficient balance for deployment"
    echo "   Need at least 0.001 ETH, have $BALANCE_ETH ETH"
    echo "   Get testnet ETH from:"
    echo "   - https://portal.cdp.coinbase.com/products/faucet"
    echo "   - https://www.alchemy.com/faucets/base-sepolia"
    echo "   - https://thirdweb.com/base-sepolia-testnet"
    exit 1
fi

echo "✅ Sufficient balance found: $BALANCE_ETH ETH"

# Deploy contracts
echo ""
echo "🏗️  Deploying contracts to Base Sepolia..."
echo "   Deployer: $DEPLOYER_ADDRESS"
echo "   Network: Base Sepolia ($CHAIN_ID)"
echo "   RPC: $RPC_URL"
echo ""

# Run the deployment script
echo "🔍 Checking for Basescan API key..."
if [ -n "$BASESCAN_API_KEY" ]; then
    echo "✅ Basescan API key found, will verify contracts"
    PRIVATE_KEY=$PRIVATE_KEY forge script script/Deploy.s.sol \
        --rpc-url $RPC_URL \
        --broadcast \
        --verify \
        --etherscan-api-key $BASESCAN_API_KEY \
        -vvvv
else
    echo "⚠️  No BASESCAN_API_KEY found, deploying without verification"
    PRIVATE_KEY=$PRIVATE_KEY forge script script/Deploy.s.sol \
        --rpc-url $RPC_URL \
        --broadcast \
        -vvvv
fi

if [ $? -ne 0 ]; then
    echo "❌ Deployment failed!"
    exit 1
fi

echo ""
echo "✅ Deployment successful!"

# Parse the deployment addresses from broadcast logs
BROADCAST_DIR="broadcast/Deploy.s.sol/$CHAIN_ID"
if [ -d "$BROADCAST_DIR" ]; then
    # Find the latest run file
    LATEST_RUN=$(ls -t $BROADCAST_DIR/run-latest.json 2>/dev/null || ls -t $BROADCAST_DIR/run-*.json | head -1)
    
    if [ -f "$LATEST_RUN" ]; then
        echo "📄 Parsing deployment addresses..."
        
        # Extract contract addresses from the broadcast log
        MOCK_IDENTITY_REGISTRY=$(jq -r '.transactions[] | select(.contractName == "MockIdentityRegistry") | .contractAddress' "$LATEST_RUN")
        SEAL_REGISTRY=$(jq -r '.transactions[] | select(.contractName == "SealRegistry") | .contractAddress' "$LATEST_RUN")
        
        if [ "$MOCK_IDENTITY_REGISTRY" != "null" ] && [ "$SEAL_REGISTRY" != "null" ]; then
            # Update deployment file
            TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
            TX_HASH=$(jq -r '.transactions[0].hash' "$LATEST_RUN")
            
            cat > deployments/base-sepolia.json << EOF
{
  "network": "base-sepolia",
  "chainId": $CHAIN_ID,
  "deployer": "$DEPLOYER_ADDRESS",
  "contracts": {
    "MockIdentityRegistry": "$MOCK_IDENTITY_REGISTRY",
    "SealRegistry": "$SEAL_REGISTRY"
  },
  "deployedAt": "$TIMESTAMP",
  "txHash": "$TX_HASH"
}
EOF
            
            echo "✅ Updated deployments/base-sepolia.json"
        else
            echo "⚠️  Could not parse contract addresses from broadcast logs"
        fi
    fi
fi

echo ""
echo "🎉 Deployment Complete!"
echo "======================="
echo "Network:              Base Sepolia"
echo "MockIdentityRegistry: $MOCK_IDENTITY_REGISTRY"
echo "SealRegistry:         $SEAL_REGISTRY"
echo "Deployer:             $DEPLOYER_ADDRESS"
echo ""
echo "🔍 Verification:"
echo "Check contracts on Basescan:"
echo "https://sepolia.basescan.org/address/$MOCK_IDENTITY_REGISTRY"
echo "https://sepolia.basescan.org/address/$SEAL_REGISTRY"
echo ""
echo "📝 Next Steps:"
echo "1. Verify contracts were deployed correctly"
if [ -z "$BASESCAN_API_KEY" ]; then
echo "2. Manually verify contracts on Basescan:"
echo "   forge verify-contract $MOCK_IDENTITY_REGISTRY MockIdentityRegistry --chain base-sepolia"
echo "   forge verify-contract $SEAL_REGISTRY SealRegistry --chain base-sepolia"
echo "3. Run test interactions with script/Interact.s.sol"
echo "4. Update project documentation with deployed addresses"
echo "5. Register test agents via MockIdentityRegistry.addAgent()"
else
echo "2. Run test interactions with script/Interact.s.sol"
echo "3. Update project documentation with deployed addresses"
echo "4. Register test agents via MockIdentityRegistry.addAgent()"
fi

# Clean up sensitive data
unset PRIVATE_KEY
unset SECRET_JSON