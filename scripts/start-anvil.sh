#!/bin/bash
# Start Anvil (local Ethereum node for guardian registry)
# Usage: ./scripts/start-anvil.sh

set -euo pipefail
source "$(dirname "$0")/common.sh"

[[ -f "${WORKSPACE_ROOT}/configs/guardian-0.conf" ]] && source "${WORKSPACE_ROOT}/configs/guardian-0.conf"

PORT="${ANVIL_PORT:-8545}"
HOST="${ANVIL_HOST:-0.0.0.0}"
CHAIN_ID="${ANVIL_CHAIN_ID:-31337}"
PID_FILE="${WORKSPACE_ROOT}/anvil.pid"
LOG_FILE="${WORKSPACE_ROOT}/logs/anvil.log"
STATE_FILE="${WORKSPACE_ROOT}/data/anvil-state.json"

command_exists anvil || { log_error "Anvil not installed. Install: curl -L https://foundry.paradigm.xyz | bash && foundryup"; exit 1; }
is_running "$PID_FILE" && { log_warn "Already running"; exit 1; }

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$STATE_FILE")"

nohup anvil --host "$HOST" --port "$PORT" --chain-id "$CHAIN_ID" \
    --accounts 10 --balance 10000 --block-time 1 \
    --state "$STATE_FILE" --state-interval 60 >> "$LOG_FILE" 2>&1 &
echo "$!" > "$PID_FILE"
sleep 2

kill -0 "$(cat "$PID_FILE")" 2>/dev/null && log_success "Anvil started on $HOST:$PORT" || { log_error "Failed"; exit 1; }
