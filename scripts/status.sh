#!/bin/bash
# Check guardian status
# Usage: ./status.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config/guardian.conf"

PID_FILE="$ROOT_DIR/data/guardian-${GUARDIAN_INDEX}.pid"
LOG_PATH="$ROOT_DIR/$LOG_FILE"

echo "================================"
echo "Guardian-$GUARDIAN_INDEX Status"
echo "================================"

# Check process
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Status: RUNNING (PID: $PID)"
        
        # Memory usage
        MEM=$(ps -o rss= -p "$PID" 2>/dev/null | awk '{print int($1/1024)"MB"}')
        echo "Memory: $MEM"
    else
        echo "Status: DEAD (stale PID)"
    fi
else
    echo "Status: STOPPED"
fi

echo ""
echo "Endpoints:"
echo "  gRPC:    0.0.0.0:$GRPC_PORT"
echo "  Metrics: http://0.0.0.0:$STATUS_PORT/metrics"

echo ""
echo "Recent logs:"
echo "------------"
tail -10 "$LOG_PATH" 2>/dev/null || echo "(no logs)"

