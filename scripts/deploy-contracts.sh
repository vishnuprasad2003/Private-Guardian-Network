#!/bin/bash
# Deploy Wormhole contracts to a chain
# Usage: ./deploy-contracts.sh <chain> <rpc_url> <guardian_addresses>
# Example: ./deploy-contracts.sh geth http://localhost:8545 "0xAAA...,0xBBB...,0xCCC..."

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ARTIFACTS="$ROOT_DIR/contracts/avalanche/artifacts"

CHAIN="$1"
RPC_URL="$2"
GUARDIANS="$3"
PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

if [ -z "$CHAIN" ] || [ -z "$RPC_URL" ] || [ -z "$GUARDIANS" ]; then
    echo "Usage: ./deploy-contracts.sh <chain> <rpc_url> <guardian_addresses>"
    echo "  chain: geth, avalanche"
    echo "  guardian_addresses: comma-separated list of addresses"
    exit 1
fi

# Get chain ID
CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
echo "Deploying to chain ID: $CHAIN_ID"

# Wormhole chain IDs
case "$CHAIN" in
    geth) WORMHOLE_CHAIN_ID=2 ;;
    avalanche) WORMHOLE_CHAIN_ID=6 ;;
    *) WORMHOLE_CHAIN_ID=2 ;;
esac

# Format guardians for Solidity
IFS=',' read -ra ADDR_ARRAY <<< "$GUARDIANS"
GUARDIAN_ARRAY="["
for addr in "${ADDR_ARRAY[@]}"; do
    GUARDIAN_ARRAY+="$addr,"
done
GUARDIAN_ARRAY="${GUARDIAN_ARRAY%,}]"

echo "Guardians: $GUARDIAN_ARRAY"

# Deploy Implementation
echo "Deploying Implementation..."
IMPL=$(cast send --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" \
    --create "$(cat "$ARTIFACTS/Implementation.bytecode")" --json | jq -r '.contractAddress')
echo "Implementation: $IMPL"

# Deploy Setup
echo "Deploying Setup..."
SETUP=$(cast send --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" \
    --create "$(cat "$ARTIFACTS/Setup.bytecode")" --json | jq -r '.contractAddress')
echo "Setup: $SETUP"

# Create setup calldata
SETUP_DATA=$(cast calldata "setup(address,address[],uint16,uint16,bytes32,uint256)" \
    "$IMPL" \
    "$GUARDIAN_ARRAY" \
    "$WORMHOLE_CHAIN_ID" \
    "$WORMHOLE_CHAIN_ID" \
    "0x0000000000000000000000000000000000000000000000000000000000000001" \
    "$CHAIN_ID")

# Deploy Wormhole proxy
echo "Deploying Wormhole..."
CONSTRUCTOR=$(cast abi-encode "constructor(address,bytes)" "$SETUP" "$SETUP_DATA" | cut -c3-)
WORMHOLE=$(cast send --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" \
    --create "$(cat "$ARTIFACTS/Wormhole.bytecode")$CONSTRUCTOR" --json | jq -r '.contractAddress')

echo ""
echo "================================"
echo "Deployment Complete"
echo "================================"
echo "Chain: $CHAIN (ID: $CHAIN_ID)"
echo "Wormhole Contract: $WORMHOLE"
echo ""
echo "Add to guardian.conf:"
if [ "$CHAIN" = "geth" ]; then
    echo "  GETH_CONTRACT=\"$WORMHOLE\""
elif [ "$CHAIN" = "avalanche" ]; then
    echo "  AVALANCHE_CONTRACT=\"$WORMHOLE\""
fi

