# Private Guardian Network - Deployment Guide

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        PRIVATE GUARDIAN NETWORK                             │
│                                                                             │
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                  │
│   │  Guardian 0 │     │  Guardian 1 │     │  Guardian 2 │                  │
│   │   (VM 1)    │◄───►│   (VM 2)    │◄───►│   (VM 3)    │                  │
│   └──────┬──────┘     └──────┬──────┘     └──────┬──────┘                  │
│          │                   │                   │                          │
│          └───────────────────┼───────────────────┘                          │
│                              │ P2P Network                                  │
│                              │                                              │
│   ┌──────────────────────────┼──────────────────────────┐                  │
│   │                          │                          │                  │
│   ▼                          ▼                          ▼                  │
│ ┌─────────────┐      ┌─────────────┐      ┌─────────────┐                  │
│ │Private Geth │      │Avalanche L1 │      │   Solana    │                  │
│ │ (Registry)  │      │  (Subnet)   │      │  (Cluster)  │                  │
│ │   VM 0      │      │   Azure     │      │   VM 4+     │                  │
│ └─────────────┘      └─────────────┘      └─────────────┘                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## VM Requirements

| VM | Role | Hostname | Specs | Ports |
|----|------|----------|-------|-------|
| VM 0 | Private Geth (Registry) | geth-node | 2 vCPU, 4GB RAM, 50GB SSD | 8545, 8546 |
| VM 1 | Guardian 0 (Bootstrap) | **guardian-0** | 2 vCPU, 4GB RAM, 20GB SSD | 8999, 7000, 6600 |
| VM 2 | Guardian 1 | **guardian-1** | 2 vCPU, 4GB RAM, 20GB SSD | 8999, 7000, 6600 |
| VM 3 | Guardian 2 | **guardian-2** | 2 vCPU, 4GB RAM, 20GB SSD | 8999, 7000, 6600 |

> **⚠️ CRITICAL: Hostname Requirement**
>
> Guardian VMs **MUST** have hostname set to `guardian-X` where X is the guardian index.
> This is required for private networks with custom chain IDs.
>
> Set hostname permanently:
> ```bash
> sudo hostnamectl set-hostname guardian-0  # For VM 1
> sudo hostnamectl set-hostname guardian-1  # For VM 2
> sudo hostnamectl set-hostname guardian-2  # For VM 3
> ```

## Deployment Steps

### Phase 1: Preparation (Local Machine)

#### 1.1 Generate Guardian Keys

```bash
cd Private-Guardian-Network

# Generate keys for each guardian
./scripts/keygen.sh 0
./scripts/keygen.sh 1
./scripts/keygen.sh 2

# Note the addresses output - you'll need them for contract deployment
# Example output:
# Guardian 0: 0xAAA...
# Guardian 1: 0xBBB...
# Guardian 2: 0xCCC...
```

#### 1.2 Update Configuration

Edit `config/guardian.conf` with your guardian addresses:
```bash
GUARDIAN_0_ADDRESS="0xAAA..."
GUARDIAN_1_ADDRESS="0xBBB..."
GUARDIAN_2_ADDRESS="0xCCC..."
```

### Phase 2: Deploy Private Geth (VM 0)

#### 2.1 Clone Repository

```bash
# On VM 0
git clone <your-repo> /opt/guardian
cd /opt/guardian
```

#### 2.2 Setup and Start Geth

```bash
sudo ./scripts/setup.sh
./scripts/deploy-geth.sh
```

#### 2.3 Deploy Wormhole Contract

```bash
# Get guardian addresses (comma-separated)
GUARDIANS="0xAAA...,0xBBB...,0xCCC..."

# Deploy
./scripts/deploy-contracts.sh geth http://localhost:8545 "$GUARDIANS"

# Note the contract address and update config/guardian.conf:
# GETH_CONTRACT="0x..."
```

### Phase 3: Deploy Contracts to Avalanche L1

```bash
# From any machine with network access to Avalanche
export PRIVATE_KEY="your_deployer_private_key"

./scripts/deploy-contracts.sh avalanche \
    "http://20.253.174.32:80/ext/bc/.../rpc" \
    "$GUARDIANS"

# Update config/guardian.conf:
# AVALANCHE_CONTRACT="0x..."
```

### Phase 4: Deploy Guardian Nodes

#### 4.1 VM 1 (Guardian 0 - Bootstrap Node)

```bash
# Clone and setup
git clone <your-repo> /opt/guardian
cd /opt/guardian
sudo ./scripts/setup.sh

# Copy key
cp /path/to/guardian-0.key keys/

# Edit config
nano config/guardian.conf
# Set:
#   GUARDIAN_INDEX=0
#   GETH_RPC="ws://VM0_IP:8546"
#   GETH_CONTRACT="0x..."
#   AVALANCHE_RPC="ws://..."
#   AVALANCHE_CONTRACT="0x..."
#   BOOTSTRAP_PEERS=""  # Empty for guardian-0

# Start
./scripts/start.sh

# Get peer ID for other guardians
grep "peer_id" logs/guardian-0.log
# Output: "peer_id": "12D3KooW..."
```

#### 4.2 VM 2 (Guardian 1)

```bash
# Same setup as VM 1, then:

nano config/guardian.conf
# Set:
#   GUARDIAN_INDEX=1
#   BOOTSTRAP_PEERS="/ip4/VM1_IP/udp/8999/quic-v1/p2p/12D3KooW..."

./scripts/start.sh
```

#### 4.3 VM 3 (Guardian 2)

```bash
# Same as Guardian 1 with GUARDIAN_INDEX=2
```

### Phase 5: Deploy Solana Bridge

```bash
# On Solana validator machine
solana program deploy contracts/solana/artifacts/bridge.so

# Initialize with same guardians (without 0x prefix)
cd WormHole-Official-GitHub-Repo/solana/scripts
npm install

RPC_URL="http://localhost:8899" \
CORE_BRIDGE_PROGRAM_ID="<program_id>" \
PRIVATE_KEY="~/.config/solana/id.json" \
GUARDIAN_SET='["AAA...","BBB...","CCC..."]' \
npx ts-node initialize-core.ts

# Update guardian config with Solana details
```

### Phase 6: Verify Network

```bash
# On each guardian VM
./scripts/status.sh

# Check P2P connections
grep "Connected to bootstrap" logs/guardian-*.log

# Check chain watchers
grep "watching" logs/guardian-*.log
```

## Operations

### Start/Stop/Status

```bash
./scripts/start.sh      # Start guardian
./scripts/stop.sh       # Stop guardian
./scripts/status.sh     # Check status
./scripts/logs.sh -f    # Follow logs
```

### Using Systemd (Recommended)

```bash
sudo systemctl start guardian
sudo systemctl stop guardian
sudo systemctl status guardian
sudo journalctl -u guardian -f
```

### Publishing Messages

```bash
# Avalanche L1
cast send $AVALANCHE_CONTRACT \
    "publishMessage(uint32,bytes,uint8)" \
    1 0x48656c6c6f 1 \
    --rpc-url $AVALANCHE_RPC \
    --private-key $PRIVATE_KEY
```

### Fetching VAAs

```bash
# Using grpcurl
grpcurl -plaintext -d '{
  "message_id": {
    "emitter_chain": 6,
    "emitter_address": "000000000000000000000000<your_wallet>",
    "sequence": "1"
  }
}' localhost:7000 publicrpc.v1.PublicRPCService/GetSignedVAA
```

## Troubleshooting

### Guardian Won't Start

1. Check key file exists: `ls -la keys/`
2. Check config: `cat config/guardian.conf`
3. Check logs: `./scripts/logs.sh`

### P2P Connection Failed

1. Verify firewall allows UDP 8999
2. Check bootstrap peer format includes peer ID
3. Ensure guardian-0 is running first

### VAA Not Found

1. Verify guardian set matches across all chains
2. Check quorum (need 2/3+1 signatures)
3. Wait for block finality (~15 seconds)

### Logs Filling Disk

1. Verify logrotate is configured: `cat /etc/logrotate.d/guardian`
2. Manual cleanup: `find logs/ -name "*.log.*" -mtime +7 -delete`

## Security Checklist

- [ ] Guardian keys stored with 600 permissions
- [ ] Private Geth only accessible from guardian VMs
- [ ] Firewall configured (only required ports open)
- [ ] SSH key authentication only
- [ ] Regular key rotation schedule
- [ ] Monitoring and alerting configured
- [ ] Backup strategy for keys and data

## Configuration Reference

See `config/guardian.conf` for all available options.

Key settings:
- `GUARDIAN_INDEX`: Unique identifier (0, 1, 2, ...)
- `GETH_RPC`: Private Ethereum WebSocket URL
- `AVALANCHE_RPC`: Avalanche L1 WebSocket URL
- `SOLANA_RPC`: Solana HTTP URL
- `BOOTSTRAP_PEERS`: Guardian-0's multiaddr (empty for guardian-0)
- `LOG_MAX_AGE_DAYS`: Log rotation interval

