#!/bin/bash
# View guardian logs
# Usage: ./logs.sh [--follow | -n LINES]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config/guardian.conf"

LOG_PATH="$ROOT_DIR/$LOG_FILE"

if [ ! -f "$LOG_PATH" ]; then
    echo "No log file found: $LOG_PATH"
    exit 1
fi

case "$1" in
    --follow|-f)
        tail -f "$LOG_PATH"
        ;;
    -n)
        tail -n "${2:-50}" "$LOG_PATH"
        ;;
    *)
        tail -n 50 "$LOG_PATH"
        ;;
esac

