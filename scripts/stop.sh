#!/bin/bash
# Stop guardian node
# Usage: ./stop.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config/guardian.conf"

PID_FILE="$ROOT_DIR/data/guardian-${GUARDIAN_INDEX}.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "Guardian not running (no PID file)"
    exit 0
fi

PID=$(cat "$PID_FILE")

if ! kill -0 "$PID" 2>/dev/null; then
    echo "Guardian not running (stale PID)"
    rm -f "$PID_FILE"
    exit 0
fi

echo "Stopping guardian-$GUARDIAN_INDEX (PID: $PID)..."
kill "$PID"

# Wait for graceful shutdown
for i in {1..10}; do
    if ! kill -0 "$PID" 2>/dev/null; then
        rm -f "$PID_FILE"
        echo "Stopped"
        exit 0
    fi
    sleep 1
done

# Force kill
echo "Force killing..."
kill -9 "$PID" 2>/dev/null || true
rm -f "$PID_FILE"
echo "Stopped"

