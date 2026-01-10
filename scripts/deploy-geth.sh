#!/bin/bash
# Deploy private Geth node and Wormhole contracts
# Run this on the VM that will host the guardian registry
# Usage: ./deploy-geth.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config/guardian.conf"

GETH_DATA="$ROOT_DIR/data/geth"
GETH_PORT=30303
GETH_HTTP_PORT=8545
GETH_WS_PORT=8546

echo "================================"
echo "Private Geth Deployment"
echo "================================"

# Check geth
if ! command -v geth &> /dev/null; then
    echo "Installing Geth..."
    sudo add-apt-repository -y ppa:ethereum/ethereum
    sudo apt-get update
    sudo apt-get install -y ethereum
fi

# Initialize if needed
if [ ! -d "$GETH_DATA/geth" ]; then
    echo "Initializing Geth..."
    mkdir -p "$GETH_DATA"
    
    # Create genesis file
    cat > "$GETH_DATA/genesis.json" << 'EOF'
{
  "config": {
    "chainId": 31337,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "berlinBlock": 0,
    "londonBlock": 0
  },
  "alloc": {
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266": {
      "balance": "10000000000000000000000"
    }
  },
  "difficulty": "1",
  "gasLimit": "30000000"
}
EOF
    
    geth init --datadir "$GETH_DATA" "$GETH_DATA/genesis.json"
fi

# Start Geth
echo "Starting Geth..."
nohup geth \
    --datadir "$GETH_DATA" \
    --networkid 31337 \
    --http --http.addr 0.0.0.0 --http.port $GETH_HTTP_PORT \
    --http.api eth,net,web3,personal \
    --ws --ws.addr 0.0.0.0 --ws.port $GETH_WS_PORT \
    --ws.api eth,net,web3,personal \
    --allow-insecure-unlock \
    --mine --miner.threads 1 \
    --nodiscover \
    >> "$ROOT_DIR/logs/geth.log" 2>&1 &

echo $! > "$ROOT_DIR/data/geth.pid"
sleep 5

echo "Geth running at:"
echo "  HTTP: http://0.0.0.0:$GETH_HTTP_PORT"
echo "  WS:   ws://0.0.0.0:$GETH_WS_PORT"
echo ""
echo "Next: Deploy Wormhole contracts with deploy-contracts.sh"

