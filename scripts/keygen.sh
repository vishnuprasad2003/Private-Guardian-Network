#!/bin/bash
# Generate guardian and node keys
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config/guardian.conf"

GUARDIAND="${GUARDIAND_BIN:-$ROOT_DIR/../WormHole-Official-GitHub-Repo/build/bin/guardiand}"
IDX="${1:-0}"
KEYS_DIR="$ROOT_DIR/keys"

mkdir -p "$KEYS_DIR"
chmod 700 "$KEYS_DIR"

GUARDIAN_KEY="$KEYS_DIR/guardian-${IDX}.key"
NODE_KEY="$KEYS_DIR/node-${IDX}.key"

if [ -f "$GUARDIAN_KEY" ]; then
    echo "Guardian key already exists: $GUARDIAN_KEY"
else
    echo "Generating guardian key for guardian-${IDX}..."
    "$GUARDIAND" keygen "$GUARDIAN_KEY" --desc "Guardian ${IDX}"
    echo "Generated: $GUARDIAN_KEY"
fi

if [ -f "$NODE_KEY" ]; then
    echo "Node key already exists: $NODE_KEY"
else
    echo "Generating node key for guardian-${IDX}..."
    "$GUARDIAND" keygen "$NODE_KEY" --block-type "WORMHOLE NODE PRIVATE KEY" --desc "Guardian ${IDX} P2P"
    echo "Generated: $NODE_KEY"
fi

# Extract addresses
GUARDIAN_ADDR=$(grep "PublicKey:" "$GUARDIAN_KEY" | cut -d: -f2 | tr -d ' ')
echo ""
echo "Guardian ${IDX} Address: $GUARDIAN_ADDR"
echo "Add this address to the guardian set in your Wormhole contracts!"
