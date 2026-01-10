#!/bin/bash
# Start VAA API Server
# Usage: ./scripts/start-api.sh [--port 3000] [--host 0.0.0.0]

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "Error: Node.js is not installed"
    exit 1
fi

# Check if dependencies are installed
if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    npm install
fi

# Check if guardian is running
ADMIN_SOCKET="${ROOT_DIR}/data/guardian-0.sock"
if [ ! -S "$ADMIN_SOCKET" ]; then
    echo "Warning: Guardian socket not found at $ADMIN_SOCKET"
    echo "Make sure the guardian is running: ./scripts/start.sh"
    exit 1
fi

# Start API server
echo "Starting VAA API Server..."
node scripts/vaa-api-server.js "$@"

