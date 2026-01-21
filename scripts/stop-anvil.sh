#!/bin/bash
# Stop Anvil
# Usage: ./scripts/stop-anvil.sh

set -euo pipefail
source "$(dirname "$0")/common.sh"

PID_FILE="/solana/wormhole/anvil.pid"
is_running "$PID_FILE" || { log_warn "Not running"; exit 0; }

PID=$(cat "$PID_FILE")
kill "$PID" 2>/dev/null || true
rm -f "$PID_FILE"
log_success "Anvil stopped"
