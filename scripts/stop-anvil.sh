#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Stop Anvil
# Usage: ./scripts/stop-anvil.sh [config-file]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
source "$(dirname "$0")/common.sh"

CONFIG="${1:-${WORKSPACE_ROOT}/configs/guardian-0.conf}"
load_config "$CONFIG"

PID_FILE="${BASE_DIR}/pids/anvil.pid"
graceful_stop "$PID_FILE" "Anvil" 5
