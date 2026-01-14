#!/bin/bash
# Start guardian node
# Usage: ./scripts/start-guardian.sh [config-file]
#
# For unsafeDevMode, set hostname first:
#   sudo hostname guardian-0   (for guardian-0)
#   sudo hostname guardian-1   (for guardian-1)

set -euo pipefail
source "$(dirname "$0")/common.sh"

CONFIG="${1:-${WORKSPACE_ROOT}/configs/guardian-0.conf}"
load_config "$CONFIG" || exit 1

log_info "Starting $GUARDIAN_NAME"

is_running "$PID_FILE" && { log_warn "Already running (PID: $(cat "$PID_FILE"))"; exit 1; }
validate_guardiand || exit 1

# Check hostname for unsafeDevMode
if [[ "${UNSAFE_DEV_MODE:-false}" == "true" ]]; then
    EXPECTED_HOSTNAME="guardian-${GUARDIAN_INDEX}"
    CURRENT_HOSTNAME=$(hostname)
    if [[ "$CURRENT_HOSTNAME" != "$EXPECTED_HOSTNAME" ]]; then
        log_error "Hostname must be '$EXPECTED_HOSTNAME' for unsafeDevMode"
        log_info "Run: sudo hostname $EXPECTED_HOSTNAME"
        exit 1
    fi
fi

# Clean up previous data (for fresh start)
if [[ -d "$DATA_DIR" ]]; then
    log_info "Cleaning up previous data..."
    rm -rf "$DATA_DIR"
fi
rm -f "$KEY_FILE" "$NODE_KEY_FILE" "$ADMIN_SOCKET" "$GRPC_SOCKET" 2>/dev/null || true

create_directories
handle_unsafe_dev_keys || exit 1

# Build arguments
ARGS=(
    "node"
    "--network" "$NETWORK_ID"
    "--nodeName" "$GUARDIAN_NAME"
    "--port" "$P2P_PORT"
    "--statusAddr" "0.0.0.0:$STATUS_PORT"
    "--publicRPC" "0.0.0.0:$GRPC_PORT"
    "--publicGRPCSocket" "$GRPC_SOCKET"
    "--adminSocket" "$ADMIN_SOCKET"
    "--dataDir" "$DATA_DIR"
    "--logLevel" "$LOG_LEVEL"
    "--guardianKey" "$KEY_FILE"
    "--nodeKey" "$NODE_KEY_FILE"
)

# Chain connections
[[ -n "${GETH_RPC:-}" ]] && ARGS+=("--ethRPC" "$GETH_RPC" "--ethContract" "$GETH_CONTRACT")
[[ -n "${AVALANCHE_RPC:-}" ]] && ARGS+=("--avalancheRPC" "$AVALANCHE_RPC" "--avalancheContract" "$AVALANCHE_CONTRACT")
[[ -n "${SOLANA_RPC:-}" ]] && [[ -n "${SOLANA_CONTRACT:-}" ]] && ARGS+=("--solanaRPC" "$SOLANA_RPC" "--solanaContract" "$SOLANA_CONTRACT")
[[ -n "${BOOTSTRAP_PEERS:-}" ]] && ARGS+=("--bootstrap" "$BOOTSTRAP_PEERS")
[[ "${DISABLE_TELEMETRY:-false}" == "true" ]] && ARGS+=("--disableTelemetry")
[[ "${UNSAFE_DEV_MODE:-false}" == "true" ]] && ARGS+=("--unsafeDevMode")

# Start
log_info "Command: $GUARDIAND_BIN ${ARGS[*]}"
nohup "$GUARDIAND_BIN" "${ARGS[@]}" >> "$LOG_FILE" 2>&1 &
echo "$!" > "$PID_FILE"
sleep 3

if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    log_success "Started (PID: $(cat "$PID_FILE"))"
    log_info "Logs: tail -f $LOG_FILE"
    log_info "gRPC: localhost:$GRPC_PORT"
    
    # Show peer ID for bootstrap
    sleep 2
    PEER_ID=$(grep "Node has been started" "$LOG_FILE" 2>/dev/null | grep -oP 'peer_id": "\K[^"]+' | tail -1 || true)
    if [[ -n "$PEER_ID" ]]; then
        log_info "Peer ID: $PEER_ID"
        log_info "Bootstrap: /ip4/127.0.0.1/udp/$P2P_PORT/quic-v1/p2p/$PEER_ID"
    fi
else
    log_error "Failed to start. Check logs:"
    tail -20 "$LOG_FILE"
    exit 1
fi
