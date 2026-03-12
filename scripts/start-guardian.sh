#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Start a guardian node
# Usage: ./scripts/start-guardian.sh <config-file>
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
source "$(dirname "$0")/common.sh"

CONFIG="${1:?Usage: $0 <config-file>}"
load_config "$CONFIG"
ensure_dirs

log_info "Starting ${GUARDIAN_NAME}"

# ── Pre-flight checks ──────────────────────────────────────────────────────
is_running "$PID_FILE" && { log_warn "Already running (PID $(cat "$PID_FILE"))"; exit 1; }
validate_guardiand

if [[ "${UNSAFE_DEV_MODE:-false}" == "true" ]]; then
    local_host=$(hostname)
    expected="guardian-${GUARDIAN_INDEX}"
    [[ "$local_host" != "$expected" ]] && {
        log_error "Hostname must be '${expected}' for unsafeDevMode (current: ${local_host})"
        log_info  "Run: sudo hostname ${expected}"
        exit 1
    }
fi

# ── Clean stale state (devMode always starts fresh) ─────────────────────────
[[ -d "$DATA_DIR" ]] && { log_info "Cleaning previous data..."; rm -rf "$DATA_DIR"; }
rm -f "$KEY_FILE" "$NODE_KEY_FILE" "$ADMIN_SOCKET" "$GRPC_SOCKET" 2>/dev/null || true
mkdir -p "$DATA_DIR"

# ── Log rotation (if log file exists and is large) ──────────────────────────
LOG_MAX_SIZE="${LOG_MAX_SIZE:-100M}"
if [[ -f "$LOG_FILE" ]]; then
    # Check if log file exceeds max size (convert to bytes for comparison)
    if command_exists stat; then
        LOG_SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
        MAX_BYTES=$(echo "$LOG_MAX_SIZE" | sed 's/M$/*1024*1024/;s/K$/*1024/' | bc 2>/dev/null || echo "104857600")
        if [[ "$LOG_SIZE" -gt "$MAX_BYTES" ]]; then
            log_info "Rotating log file (size: ${LOG_SIZE} bytes)"
            LOG_BACKUP="${LOG_FILE}.$(date +%Y%m%d_%H%M%S)"
            mv "$LOG_FILE" "$LOG_BACKUP"
            [[ "${LOG_COMPRESS:-false}" == "true" ]] && gzip "$LOG_BACKUP" 2>/dev/null || true
            # Keep only last N files
            ls -t "${LOG_FILE}".* 2>/dev/null | tail -n +$((LOG_MAX_FILES + 1)) | xargs rm -f 2>/dev/null || true
        fi
    fi
fi

# In unsafeDevMode, delete old key so guardiand regenerates deterministically
if [[ "${UNSAFE_DEV_MODE:-false}" == "true" ]]; then
    rm -f "$KEY_FILE"
fi

# ── Build argument list ─────────────────────────────────────────────────────
ARGS=(
    node
    --network      "$NETWORK_ID"
    --nodeName     "$GUARDIAN_NAME"
    --port         "$P2P_PORT"
    --statusAddr   "0.0.0.0:${STATUS_PORT}"
    --publicRPC    "0.0.0.0:${GRPC_PORT}"
    --publicGRPCSocket "$GRPC_SOCKET"
    --adminSocket      "$ADMIN_SOCKET"
    --dataDir          "$DATA_DIR"
    --logLevel         "$LOG_LEVEL"
    --guardianKey      "$KEY_FILE"
    --nodeKey          "$NODE_KEY_FILE"
)

# Chain connections (EVM = WS for subscriptions; Solana = HTTP polling)
[[ -n "${GETH_RPC:-}" ]]      && ARGS+=(--ethRPC "$GETH_RPC" --ethContract "$GETH_CONTRACT")
[[ -n "${AVALANCHE_RPC:-}" ]] && ARGS+=(--avalancheRPC "$AVALANCHE_RPC" --avalancheContract "$AVALANCHE_CONTRACT")
[[ -n "${BSC_RPC:-}" ]]       && ARGS+=(--bscRPC "$BSC_RPC" --bscContract "$BSC_CONTRACT")
[[ -n "${SOLANA_RPC:-}" && -n "${SOLANA_CONTRACT:-}" ]] && ARGS+=(--solanaRPC "$SOLANA_RPC" --solanaContract "$SOLANA_CONTRACT")
[[ -n "${BOOTSTRAP_PEERS:-}" ]]                && ARGS+=(--bootstrap "$BOOTSTRAP_PEERS")
[[ "${DISABLE_TELEMETRY:-false}" == "true" ]]  && ARGS+=(--disableTelemetry)
[[ "${UNSAFE_DEV_MODE:-false}" == "true" ]]    && ARGS+=(--unsafeDevMode)

# ── Launch ──────────────────────────────────────────────────────────────────
log_info "Command: ${GUARDIAND_BIN} ${ARGS[*]}"
nohup "$GUARDIAND_BIN" "${ARGS[@]}" >> "$LOG_FILE" 2>&1 &
echo "$!" > "$PID_FILE"
sleep 3

if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    log_success "Started (PID $(cat "$PID_FILE"))"
    log_info "Logs:  tail -f ${LOG_FILE}"
    log_info "gRPC:  localhost:${GRPC_PORT}"
    # Extract peer ID for bootstrap reference
    sleep 2
    PEER_ID=$(grep "Node has been started" "$LOG_FILE" 2>/dev/null \
              | grep -oP 'peer_id": "\K[^"]+' | tail -1 || true)
    [[ -n "$PEER_ID" ]] && log_info "Bootstrap: /ip4/127.0.0.1/udp/${P2P_PORT}/quic-v1/p2p/${PEER_ID}"
else
    log_error "Failed to start — last 20 log lines:"
    tail -20 "$LOG_FILE" >&2
    exit 1
fi
