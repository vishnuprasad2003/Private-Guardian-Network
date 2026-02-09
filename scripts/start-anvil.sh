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
PID_FILE="${BASE_DIR}/pids/anvil.pid"
LOG_FILE="${BASE_DIR}/logs/anvil.log"
STATE_FILE="${BASE_DIR}/data/anvil-state.json"

command_exists anvil || { log_error "Anvil not found. Run: make install-deps"; exit 1; }
is_running "$PID_FILE" && { log_warn "Anvil already running"; exit 1; }

export FOUNDRY_CACHE_DIR="${BASE_DIR}/.foundry/cache"
export FOUNDRY_DATA_DIR="${BASE_DIR}/.foundry/data"

log_info "Starting Anvil (local-only, no forking)"
log_info "State: ${STATE_FILE}"

nohup env FOUNDRY_CACHE_DIR="$FOUNDRY_CACHE_DIR" \
          FOUNDRY_DATA_DIR="$FOUNDRY_DATA_DIR" \
    anvil --host "$HOST" --port "$PORT" --chain-id "$CHAIN_ID" \
          --accounts 10 --balance 10000 --block-time 1 \
          --state "$STATE_FILE" --state-interval 60 \
          >> "$LOG_FILE" 2>&1 &
echo "$!" > "$PID_FILE"
sleep 2

if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    log_success "Anvil running on ${HOST}:${PORT}"
else
    log_error "Anvil failed to start — check ${LOG_FILE}"
    exit 1
fi
