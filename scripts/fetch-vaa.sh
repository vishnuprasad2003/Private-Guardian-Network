#!/bin/bash
# Fetch VAA from guardian node using gRPC
# Usage: ./scripts/fetch-vaa.sh <chain_id> <emitter_address> <sequence> [guardian_index]
# Example: ./scripts/fetch-vaa.sh 6 0x82E5FCe54dA7309be3e0CCc312518aC1d4d7dDD2 0 0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Check arguments
if [[ $# -lt 3 ]]; then
    log_error "Usage: $0 <chain_id> <emitter_address> <sequence> [guardian_index]"
    echo ""
    echo "Examples:"
    echo "  $0 6 0x82E5FCe54dA7309be3e0CCc312518aC1d4d7dDD2 0 0    # Fetch from guardian-0"
    echo "  $0 6 0x82E5FCe54dA7309be3e0CCc312518aC1d4d7dDD2 0 1    # Fetch from guardian-1"
    echo "  $0 6 0x82E5FCe54dA7309be3e0CCc312518aC1d4d7dDD2 0      # Fetch from guardian-0 (default)"
    echo ""
    echo "Chain IDs:"
    echo "  1 = Ethereum"
    echo "  2 = Terra"
    echo "  3 = BSC"
    echo "  4 = Polygon"
    echo "  5 = Avalanche (C-Chain)"
    echo "  6 = Avalanche (L1 Subnet)"
    echo "  10 = Solana"
    exit 1
fi

CHAIN_ID="$1"
EMITTER="$2"
SEQUENCE="$3"
GUARDIAN_INDEX="${4:-0}"

# Find grpcurl
if command -v grpcurl >/dev/null 2>&1; then
    GRPCURL_CMD="grpcurl"
elif [[ -f "$HOME/go/bin/grpcurl" ]]; then
    GRPCURL_CMD="$HOME/go/bin/grpcurl"
else
    log_error "grpcurl not found. Install it with:"
    echo "  go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest"
    exit 1
fi

# Format emitter address: remove 0x and pad to 32 bytes (64 hex chars)
EMITTER_CLEAN=$(echo "$EMITTER" | sed 's/0x//' | tr '[:upper:]' '[:lower:]')
EMITTER_PADDED=$(printf "%064s" "$EMITTER_CLEAN" | tr ' ' '0')

# Determine gRPC port
GRPC_PORT=$((7000 + GUARDIAN_INDEX))

# Proto path
PROTO_PATH="${WORKSPACE_ROOT}/../WormHole-Official-GitHub-Repo/proto"

if [[ ! -d "$PROTO_PATH" ]]; then
    log_error "Proto path not found: $PROTO_PATH"
    exit 1
fi

log_info "Fetching VAA from guardian-${GUARDIAN_INDEX}..."
log_info "Chain ID: $CHAIN_ID"
log_info "Emitter: $EMITTER -> $EMITTER_PADDED"
log_info "Sequence: $SEQUENCE"
log_info "gRPC Endpoint: localhost:${GRPC_PORT}"
echo ""

# Fetch VAA
$GRPCURL_CMD -plaintext \
  -import-path "$PROTO_PATH" \
  -proto publicrpc/v1/publicrpc.proto \
  -d "{\"message_id\": {\"emitter_chain\": $CHAIN_ID, \"emitter_address\": \"$EMITTER_PADDED\", \"sequence\": $SEQUENCE}}" \
  "localhost:${GRPC_PORT}" \
  publicrpc.v1.PublicRPCService/GetSignedVAA
