#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Stop a guardian node
# Usage: ./scripts/stop-guardian.sh <config-file>
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
source "$(dirname "$0")/common.sh"

CONFIG="${1:?Usage: $0 <config-file>}"
load_config "$CONFIG"

graceful_stop "$PID_FILE" "$GUARDIAN_NAME" 10
