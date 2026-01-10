#!/bin/bash
# Stop the private Geth node
# Usage: ./scripts/stop-geth.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PID_FILE="$ROOT_DIR/data/geth.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "Geth not running (no PID file)"
    # Try to find and kill any geth process anyway
    pkill -f "geth.*--datadir.*data/geth" 2>/dev/null && echo "Found and stopped Geth process" || echo "No Geth process found"
    exit 0
fi

PID=$(cat "$PID_FILE")

if ! kill -0 "$PID" 2>/dev/null; then
    echo "Geth not running (stale PID)"
    rm -f "$PID_FILE"
    exit 0
fi

echo "Stopping Geth (PID: $PID)..."
kill "$PID"

# Wait a bit for graceful shutdown
sleep 2

# Check if still running
if kill -0 "$PID" 2>/dev/null; then
    echo "Force stopping Geth..."
    kill -9 "$PID" 2>/dev/null || true
    sleep 1
fi

# Clean up PID file
if ! kill -0 "$PID" 2>/dev/null; then
    rm -f "$PID_FILE"
    echo "✅ Geth stopped"
else
    echo "❌ Failed to stop Geth"
    exit 1
fi

