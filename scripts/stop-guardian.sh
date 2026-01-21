#!/bin/bash
# Stop guardian node
# Usage: ./scripts/stop-guardian.sh [guardian-name]

set -euo pipefail
source "$(dirname "$0")/common.sh"

GUARDIAN_NAME="${1:-guardian-0}"
GUARDIAN_INDEX="${GUARDIAN_NAME##guardian-}"
CONFIG="${WORKSPACE_ROOT}/configs/${GUARDIAN_NAME}.conf"

# Load config to get PID_FILE path
if [[ -f "$CONFIG" ]]; then
    load_config "$CONFIG"
else
    # Fallback to absolute path if config not found
    PID_FILE="/solana/wormhole/${GUARDIAN_NAME}.pid"
fi

is_running "$PID_FILE" || { log_warn "Not running"; exit 0; }

PID=$(cat "$PID_FILE")
log_info "Stopping $GUARDIAN_NAME (PID: $PID)"
kill "$PID" 2>/dev/null || true

for i in {1..10}; do
    kill -0 "$PID" 2>/dev/null || { rm -f "$PID_FILE"; log_success "Stopped"; exit 0; }
    sleep 1
done

kill -9 "$PID" 2>/dev/null || true
rm -f "$PID_FILE"
log_success "Stopped"
