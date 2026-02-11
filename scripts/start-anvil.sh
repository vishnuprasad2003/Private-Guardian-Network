#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Start Anvil — local-only private EVM node (no mainnet forking)
# State is persisted to BASE_DIR/data/anvil-state.json
# Usage: ./scripts/start-anvil.sh [config-file]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
source "$(dirname "$0")/common.sh"

CONFIG="${1:-${WORKSPACE_ROOT}/configs/guardian-0.conf}"
load_config "$CONFIG"
ensure_dirs

PORT="${ANVIL_PORT:-8545}"
HOST="${ANVIL_HOST:-0.0.0.0}"
CHAIN_ID="${ANVIL_CHAIN_ID:-31337}"
BLOCK_TIME="${ANVIL_BLOCK_TIME:-0}"
STATE_INTERVAL="${ANVIL_STATE_INTERVAL:-0}"  # 0 = only save on shutdown (optimal for no-transaction use case)
PID_FILE="${ANVIL_PID_FILE:-${BASE_DIR}/pids/anvil.pid}"
LOG_FILE="${ANVIL_LOG_FILE:-${BASE_DIR}/logs/anvil.log}"
STATE_FILE="${ANVIL_STATE_FILE:-${BASE_DIR}/data/anvil-state.json}"

command_exists anvil || { log_error "Anvil not found. Run: make install-deps"; exit 1; }
is_running "$PID_FILE" && { log_warn "Anvil already running"; exit 1; }

export FOUNDRY_CACHE_DIR="${BASE_DIR}/.foundry/cache"
export FOUNDRY_DATA_DIR="${BASE_DIR}/.foundry/data"

# ─── Redirect ~/.foundry to BASE_DIR/.foundry (Anvil writes to ~/.foundry/anvil/tmp) ───
# Anvil creates temporary state files in ~/.foundry/anvil/tmp/ regardless of FOUNDRY_* vars.
# Create a symlink so all writes go to BASE_DIR instead of home directory.
FOUNDRY_TARGET="${BASE_DIR}/.foundry"
FOUNDRY_LINK="${HOME}/.foundry"

if [[ -L "$FOUNDRY_LINK" ]]; then
    # Already a symlink - verify it points to the right place
    if [[ "$(readlink -f "$FOUNDRY_LINK")" != "$(readlink -f "$FOUNDRY_TARGET")" ]]; then
        log_warn "~/.foundry symlink points elsewhere, updating..."
        rm -f "$FOUNDRY_LINK"
        ln -s "$FOUNDRY_TARGET" "$FOUNDRY_LINK"
    fi
elif [[ -d "$FOUNDRY_LINK" ]]; then
    # Exists as directory - preserve bin/versions, remove anvil temp files, then symlink
    log_warn "~/.foundry exists as directory, migrating to ${FOUNDRY_TARGET}..."
    
    # Stop Anvil if running to avoid file conflicts
    if is_running "$PID_FILE"; then
        log_warn "Stopping existing Anvil to migrate .foundry..."
        graceful_stop "$PID_FILE" "anvil" 5
        sleep 2
    fi
    
    # Preserve bin and versions if they exist
    mkdir -p "${FOUNDRY_TARGET}/bin" "${FOUNDRY_TARGET}/versions"
    [[ -d "${FOUNDRY_LINK}/bin" ]] && cp -r "${FOUNDRY_LINK}/bin"/* "${FOUNDRY_TARGET}/bin/" 2>/dev/null || true
    [[ -d "${FOUNDRY_LINK}/versions" ]] && cp -r "${FOUNDRY_LINK}/versions"/* "${FOUNDRY_TARGET}/versions/" 2>/dev/null || true
    
    # Remove the old directory (especially the large anvil/tmp)
    rm -rf "${FOUNDRY_LINK}/anvil" 2>/dev/null || true
    rm -rf "$FOUNDRY_LINK" 2>/dev/null || true
    
    # Create symlink
    ln -s "$FOUNDRY_TARGET" "$FOUNDRY_LINK"
    log_success "Migrated ~/.foundry → ${FOUNDRY_TARGET}"
elif [[ ! -e "$FOUNDRY_LINK" ]]; then
    # Doesn't exist - create symlink
    ln -s "$FOUNDRY_TARGET" "$FOUNDRY_LINK"
    log_info "Created ~/.foundry → ${FOUNDRY_TARGET} symlink"
fi

log_info "Starting Anvil (local-only, no forking)"
log_info "Purpose: Guardian registry storage only (no transactions after deployment)"
log_info "State file: ${STATE_FILE}"
log_info "Block time: ${BLOCK_TIME}s (0 = on-demand, only mine when transactions arrive)"

# Build Anvil command
ANVIL_CMD="anvil --host $HOST --port $PORT --chain-id $CHAIN_ID --accounts 10 --balance 10000"

# Add block-time flag (0 = on-demand mining - omit flag to enable on-demand)
if [[ "$BLOCK_TIME" == "0" ]]; then
    # Don't add --block-time flag - Anvil will mine on-demand (only when transactions arrive)
    log_info "On-demand mining enabled (blocks only created when transactions arrive)"
else
    ANVIL_CMD="$ANVIL_CMD --block-time $BLOCK_TIME"
    log_info "Block time: ${BLOCK_TIME}s (blocks created every ${BLOCK_TIME} seconds)"
fi

# Add state persistence (0 = only save on shutdown, optimal for no-transaction use case)
if [[ "$STATE_INTERVAL" == "0" ]]; then
    ANVIL_CMD="$ANVIL_CMD --state $STATE_FILE"
    log_info "State saving: Only on shutdown (no periodic saves - optimal for registry-only use)"
else
    ANVIL_CMD="$ANVIL_CMD --state $STATE_FILE --state-interval $STATE_INTERVAL"
    log_info "State saving: Every ${STATE_INTERVAL}s"
fi

nohup env FOUNDRY_CACHE_DIR="$FOUNDRY_CACHE_DIR" \
          FOUNDRY_DATA_DIR="$FOUNDRY_DATA_DIR" \
    $ANVIL_CMD >> "$LOG_FILE" 2>&1 &
echo "$!" > "$PID_FILE"
sleep 2

if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    log_success "Anvil running on ${HOST}:${PORT}"
else
    log_error "Anvil failed to start — check ${LOG_FILE}"
    exit 1
fi
