#!/bin/bash
# Start guardian node
# Usage: ./start.sh [--foreground]

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config/guardian.conf"

# Paths
GUARDIAND="${GUARDIAND_BIN:-$ROOT_DIR/../WormHole-Official-GitHub-Repo/build/bin/guardiand}"
KEY_PATH="$ROOT_DIR/$KEY_FILE"
DATA_PATH="$ROOT_DIR/$DATA_DIR"
LOG_PATH="$ROOT_DIR/$LOG_FILE"
SOCKET_PATH="$ROOT_DIR/$ADMIN_SOCKET"
PID_FILE="$ROOT_DIR/data/guardian-${GUARDIAN_INDEX}.pid"

# Validate
if [ ! -f "$GUARDIAND" ]; then
    echo "Error: guardiand not found at $GUARDIAND"
    echo "Build it first or set GUARDIAND_BIN in config"
    exit 1
fi

# Verify it's an executable (not an archive)
if ! file "$GUARDIAND" | grep -q "executable"; then
    echo "Error: $GUARDIAND is not a valid executable"
    echo "Rebuild with: cd WormHole-Official-GitHub-Repo/node && go build -o ../build/bin/guardiand ."
    exit 1
fi

# Check if already running
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Guardian already running (PID: $PID)"
        exit 1
    fi
    rm -f "$PID_FILE"
fi

# Create directories
mkdir -p "$DATA_PATH" "$(dirname "$LOG_PATH")" "$(dirname "$SOCKET_PATH")"

# Public gRPC socket path
GRPC_SOCKET_PATH="$ROOT_DIR/data/publicrpc-${GUARDIAN_INDEX}.sock"

# Build arguments
ARGS=(
    "node"
    "--network" "$NETWORK_ID"
    "--nodeName" "guardian-$GUARDIAN_INDEX"
    "--port" "$P2P_PORT"
    "--statusAddr" "0.0.0.0:$STATUS_PORT"
    "--publicRPC" "0.0.0.0:$GRPC_PORT"
    "--publicGRPCSocket" "$GRPC_SOCKET_PATH"
    "--adminSocket" "$SOCKET_PATH"
    "--dataDir" "$DATA_PATH"
    "--logLevel" "$LOG_LEVEL"
)

# Guardian key - always provide the path
# In unsafeDevMode, guardian will generate key at this path if it doesn't exist
ARGS+=("--guardianKey" "$KEY_PATH")

if [ ! -f "$KEY_PATH" ] && [ "$UNSAFE_DEV_MODE" != "true" ]; then
    echo "Error: Key file not found: $KEY_PATH"
    echo "Generate with: ./bin/genkey $KEY_PATH"
    exit 1
fi

# Node key (P2P identity) - guardian will auto-generate if not exists
NODE_KEY_PATH="$ROOT_DIR/keys/node-${GUARDIAN_INDEX}.key"
ARGS+=("--nodeKey" "$NODE_KEY_PATH")

# Ethereum (guardian registry) - REQUIRED
if [ -n "$GETH_RPC" ] && [ "$GETH_RPC" != "ws://0.0.0.0:0" ]; then
    ARGS+=("--ethRPC" "$GETH_RPC")
    ARGS+=("--ethContract" "$GETH_CONTRACT")
fi

# Avalanche
if [ -n "$AVALANCHE_RPC" ]; then
    ARGS+=("--avalancheRPC" "$AVALANCHE_RPC")
    ARGS+=("--avalancheContract" "$AVALANCHE_CONTRACT")
fi

# Solana
if [ -n "$SOLANA_RPC" ] && [ -n "$SOLANA_CONTRACT" ]; then
    ARGS+=("--solanaRPC" "$SOLANA_RPC")
    ARGS+=("--solanaContract" "$SOLANA_CONTRACT")
fi

# Bootstrap peers
if [ -n "$BOOTSTRAP_PEERS" ]; then
    ARGS+=("--bootstrap" "$BOOTSTRAP_PEERS")
fi

# Telemetry
if [ "$DISABLE_TELEMETRY" = "true" ]; then
    ARGS+=("--disableTelemetry")
fi

# Dev mode
if [ "$UNSAFE_DEV_MODE" = "true" ]; then
    ARGS+=("--unsafeDevMode")
fi

# Start
echo "Starting guardian-$GUARDIAN_INDEX..."

if [ "$1" = "--foreground" ]; then
    exec "$GUARDIAND" "${ARGS[@]}" 2>&1 | tee "$LOG_PATH"
else
    nohup "$GUARDIAND" "${ARGS[@]}" >> "$LOG_PATH" 2>&1 &
    PID=$!
    echo "$PID" > "$PID_FILE"
    sleep 2
    
    if kill -0 "$PID" 2>/dev/null; then
        echo "Started (PID: $PID)"
        echo "Logs: $LOG_PATH"
    else
        echo "Failed to start. Check logs: $LOG_PATH"
        tail -20 "$LOG_PATH"
        exit 1
    fi
fi

