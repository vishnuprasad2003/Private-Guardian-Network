#!/bin/bash
# =============================================================================
# DEPLOY WORMHOLE CONTRACTS TO EVM CHAINS
# =============================================================================
# Usage: ./scripts/deploy/deploy-evm.sh <chain> <rpc_url> <guardian_addresses>
#
# Arguments:
#   chain              - Chain name: geth, avalanche
#   rpc_url            - RPC URL for the chain
#   guardian_addresses - Comma-separated guardian addresses
#
# Environment:
#   PRIVATE_KEY        - Deployer private key (required)
#
# Example:
#   export PRIVATE_KEY="0x..."
#   ./scripts/deploy/deploy-evm.sh geth http://localhost:8545 "0xbeFA...0FBe"
#   ./scripts/deploy/deploy-evm.sh avalanche http://avalanche:8545 "0xbeFA...0FBe"
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
ARTIFACTS="$ROOT_DIR/contracts/evm/artifacts"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if [ $# -lt 3 ]; then
    echo "Usage: $0 <chain> <rpc_url> <guardian_addresses>"
    echo ""
    echo "Chains: geth, avalanche"
    echo ""
    echo "Example:"
    echo "  export PRIVATE_KEY=\"0x...\""
    echo "  $0 geth http://localhost:8545 \"0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe\""
    exit 1
fi

CHAIN="$1"
RPC_URL="$2"
GUARDIANS="$3"

# Validate
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY not set${NC}"
    exit 1
fi

if ! command -v cast &> /dev/null; then
    echo -e "${RED}Error: cast (Foundry) not installed${NC}"
    echo "Install: curl -L https://foundry.paradigm.xyz | bash && foundryup"
    exit 1
fi

# Chain ID mapping (Wormhole chain IDs)
case "$CHAIN" in
    geth)     WORMHOLE_CHAIN_ID=2 ;;
    avalanche) WORMHOLE_CHAIN_ID=6 ;;
    *)
        echo -e "${RED}Error: Unknown chain: $CHAIN${NC}"
        exit 1
        ;;
esac

echo "=============================================="
echo "Deploying Wormhole to $CHAIN"
echo "=============================================="
echo "RPC: $RPC_URL"
echo "Wormhole Chain ID: $WORMHOLE_CHAIN_ID"
echo "Guardians: $GUARDIANS"
echo ""

# Deploy Implementation
echo "Deploying Implementation..."
IMPL=$(cast send --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --create \
    "$(cat "$ARTIFACTS/Implementation.bytecode")" --json | jq -r '.contractAddress')
echo -e "${GREEN}Implementation: $IMPL${NC}"

# Deploy Setup
echo "Deploying Setup..."
SETUP=$(cast send --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --create \
    "$(cat "$ARTIFACTS/Setup.bytecode")" --json | jq -r '.contractAddress')
echo -e "${GREEN}Setup: $SETUP${NC}"

# Get chain ID for governance
NATIVE_CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
echo "Native Chain ID: $NATIVE_CHAIN_ID"

# Format guardian addresses for array (cast needs specific format)
# Convert comma-separated to space-separated for cast
GUARDIAN_LIST=$(echo "$GUARDIANS" | tr ',' ' ')

# Create setup calldata
echo "Creating setup calldata..."
SETUP_DATA=$(cast calldata "setup(address,address[],uint16,uint16,bytes32,uint256)" \
    "$IMPL" \
    "[$GUARDIANS]" \
    "$WORMHOLE_CHAIN_ID" \
    "$WORMHOLE_CHAIN_ID" \
    "0x0000000000000000000000000000000000000000000000000000000000000004" \
    "$NATIVE_CHAIN_ID")

# Deploy Wormhole proxy
echo "Deploying Wormhole proxy..."
CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,bytes)" "$SETUP" "$SETUP_DATA")
WORMHOLE=$(cast send --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --create \
    "$(cat "$ARTIFACTS/Wormhole.bytecode")${CONSTRUCTOR_ARGS:2}" --json | jq -r '.contractAddress')
echo -e "${GREEN}Wormhole: $WORMHOLE${NC}"

# Verify
echo ""
echo "Verifying deployment..."
GUARDIAN_SET=$(cast call "$WORMHOLE" "getCurrentGuardianSetIndex()(uint32)" --rpc-url "$RPC_URL")
echo "Guardian Set Index: $GUARDIAN_SET"

echo ""
echo "=============================================="
echo -e "${GREEN}Deployment Complete!${NC}"
echo "=============================================="
echo "Add to config/guardian.conf:"
if [ "$CHAIN" = "geth" ]; then
    echo "  GETH_CONTRACT=\"$WORMHOLE\""
else
    echo "  AVALANCHE_CONTRACT=\"$WORMHOLE\""
fi
echo ""

