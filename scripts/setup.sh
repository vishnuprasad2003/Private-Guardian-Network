#!/bin/bash
# Initial setup script for guardian VM
# Usage: sudo ./setup.sh

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo ./setup.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "==================================="
echo "Guardian Network - Initial Setup"
echo "==================================="

# Install dependencies
echo "[1/5] Installing dependencies..."
apt-get update -qq
apt-get install -y -qq curl jq logrotate

# Install Foundry (for cast CLI)
if ! command -v cast &> /dev/null; then
    echo "[2/5] Installing Foundry..."
    curl -L https://foundry.paradigm.xyz | bash
    source ~/.bashrc
    foundryup
else
    echo "[2/5] Foundry already installed"
fi

# Build guardiand if not present
GUARDIAND="$ROOT_DIR/../WormHole-Official-GitHub-Repo/build/bin/guardiand"
if [ ! -f "$GUARDIAND" ]; then
    echo "[3/5] Building guardiand..."
    if [ -d "$ROOT_DIR/../WormHole-Official-GitHub-Repo" ]; then
        cd "$ROOT_DIR/../WormHole-Official-GitHub-Repo/node"
        if command -v go &> /dev/null; then
            go build -o ../build/bin/guardiand ./cmd/guardiand
        else
            echo "Go not installed. Install Go 1.21+ and run: cd node && go build -o ../build/bin/guardiand ./cmd/guardiand"
        fi
    else
        echo "WormHole repo not found. Clone it first."
    fi
else
    echo "[3/5] guardiand already built"
fi

# Setup logrotate
echo "[4/5] Configuring log rotation..."
cat > /etc/logrotate.d/guardian << 'EOF'
/home/*/Private-Guardian-Network/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    size 100M
}
EOF

# Install systemd service
echo "[5/5] Installing systemd service..."
cp "$ROOT_DIR/systemd/guardian.service" /etc/systemd/system/
systemctl daemon-reload

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "1. Edit config/guardian.conf with your settings"
echo "2. Generate key: ./scripts/keygen.sh"
echo "3. Start: ./scripts/start.sh (or systemctl start guardian)"

