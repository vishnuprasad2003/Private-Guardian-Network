#!/bin/bash
# Deploy Solana Wormhole Bridge Program
# This script handles paths with spaces correctly by changing directory

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

PROGRAM_ID_FILE="contracts/solana/artifacts/program-id.json"
PROGRAM_SO="contracts/solana/artifacts/bridge.so"
SOLANA_RPC="${SOLANA_RPC:-http://127.0.0.1:8899}"

# Check if program binary exists
if [ ! -f "$PROGRAM_SO" ]; then
    echo "Error: Program binary not found: $PROGRAM_SO"
    exit 1
fi

# Check if program ID file exists
if [ ! -f "$PROGRAM_ID_FILE" ]; then
    echo "Error: Program ID file not found: $PROGRAM_ID_FILE"
    echo "Run: node scripts/deploy-solana-core.js (first run)"
    exit 1
fi

echo "Deploying Solana Wormhole Bridge Program..."
echo "  Program ID: $PROGRAM_ID_FILE"
echo "  Program Binary: $PROGRAM_SO"
echo "  RPC: $SOLANA_RPC"
echo ""

# Change to artifacts directory to avoid path issues with spaces
cd contracts/solana/artifacts

# Deploy using relative paths (no spaces in path this way)
solana program deploy \
  --program-id program-id.json \
  bridge.so \
  --url "$SOLANA_RPC"

echo ""
echo "✅ Deployment complete!"
echo "Now run: node scripts/deploy-solana-core.js (to initialize)"

