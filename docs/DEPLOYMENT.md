# Complete Deployment Guide

Step-by-step guide to deploy a private guardian network from scratch on Azure VMs.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Single Node Setup (Testing)](#single-node-setup-testing)
3. [Multi-Node Setup (Production)](#multi-node-setup-production)
4. [Systemd Services](#systemd-services)
5. [Log Rotation](#log-rotation)
6. [Firewall Rules](#firewall-rules)
7. [Monitoring](#monitoring)
8. [Backup & Recovery](#backup--recovery)

---

## Prerequisites

### Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 2 cores | 4 cores |
| RAM | 4 GB | 8 GB |
| Storage | 50 GB SSD | 100 GB SSD |
| Network | 100 Mbps | 1 Gbps |

### Software Requirements

- Ubuntu 22.04 LTS
- Internet access for package installation
- Root or sudo access

### Network Requirements

- Avalanche L1 subnet RPC accessible
- Solana cluster accessible (optional)
- Ports 8999 (UDP), 8545, 7000, 6600, 3000 (TCP) open between VMs

---

## Single Node Setup (Testing)

Complete setup for a single guardian node for testing purposes.

### Step 1: Create Azure VM

```bash
# Azure CLI
az vm create \
  --resource-group your-resource-group \
  --name guardian-0 \
  --image Ubuntu2204 \
  --size Standard_D2s_v3 \
  --admin-username azureuser \
  --generate-ssh-keys

# SSH into the VM
ssh azureuser@<VM_IP>
```

### Step 2: Clone Repository

```bash
# Create project directory
mkdir -p ~/projects
cd ~/projects

# Clone the repository
git clone https://github.com/your-org/Private-Guardian-Network.git
cd Private-Guardian-Network
```

### Step 3: Install Dependencies

```bash
# Run the dependency installer
./scripts/setup/install-deps.sh

# IMPORTANT: Reload shell to get PATH updates
source ~/.bashrc

# Verify installations
go version
node --version
cast --version
anvil --version
```

### Step 4: Clone and Build Wormhole

```bash
# Clone Wormhole repository
cd ~/projects
git clone https://github.com/wormhole-foundation/wormhole.git WormHole-Official-GitHub-Repo
cd WormHole-Official-GitHub-Repo/node

# Build guardiand
go build -o ../build/bin/guardiand .

# Verify build
../build/bin/guardiand version

# Return to project directory
cd ~/projects/Private-Guardian-Network
```

### Step 5: Install Node.js Packages

```bash
npm install
```

### Step 6: Configure

```bash
# Copy configuration template
cp config/guardian.conf.example config/guardian.conf

# Edit configuration
nano config/guardian.conf
```

Update these values in `guardian.conf`:

```bash
# For single-node testing
GUARDIAN_INDEX=0
NUM_GUARDIANS=1

# Anvil (local Ethereum)
GETH_RPC="ws://127.0.0.1:8545"
GETH_CONTRACT=""  # Will be filled after deployment

# Avalanche L1 (update with your subnet)
AVALANCHE_RPC="ws://YOUR_AVALANCHE_NODE/ext/bc/CHAIN_ID/ws"
AVALANCHE_CONTRACT=""  # Will be filled after deployment

# Solana (optional)
SOLANA_RPC="http://127.0.0.1:8899"
SOLANA_CONTRACT=""

# P2P (empty for guardian-0)
BOOTSTRAP_PEERS=""

# Enable for custom chain IDs
UNSAFE_DEV_MODE=true
```

### Step 7: Start Anvil

```bash
# Start Anvil (local Ethereum node with auto-mining)
bin/anvil start

# Verify it's running
bin/anvil status

# Check connectivity
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
  http://localhost:8545
```

### Step 8: Deploy Contracts to Anvil

```bash
# Deploy with devnet guardian address
bin/deploy anvil

# Output will show:
# Implementation: 0x...
# Setup: 0x...
# Wormhole: 0x...  <-- This is your GETH_CONTRACT

# Update guardian.conf
nano config/guardian.conf
# Set: GETH_CONTRACT="0x_FROM_DEPLOYMENT"
```

### Step 9: Deploy Contracts to Avalanche

```bash
# Set your Avalanche deployer key
export PRIVATE_KEY="your_avalanche_deployer_private_key"

# Set Avalanche RPC (HTTP, not WebSocket)
export AVALANCHE_RPC_HTTP="http://20.253.174.32:80/ext/bc/CHAIN_ID/rpc"

# Deploy
bin/deploy avalanche

# Update guardian.conf
nano config/guardian.conf
# Set: AVALANCHE_CONTRACT="0x_FROM_DEPLOYMENT"
```

### Step 10: Start Guardian

```bash
# IMPORTANT: Set hostname (required for unsafeDevMode)
sudo hostname guardian-0

# Start guardian
bin/guardian start

# Check status
bin/guardian status

# Watch logs (Ctrl+C to stop)
bin/guardian logs -f
```

Expected log output:
```
INFO Starting guardiand...
INFO Connecting to Ethereum RPC ws://127.0.0.1:8545
INFO P2P node identity: 12D3KooW...
INFO Ready to observe messages
```

### Step 11: Start API Server

```bash
bin/api start

# Verify
curl http://localhost:3000/health
# Response: {"status":"ok"}
```

### Step 12: Test End-to-End

```bash
# Publish a message on Avalanche
export WORMHOLE_ADDRESS="0x_YOUR_AVALANCHE_CONTRACT"
export RPC_URL="http://YOUR_AVALANCHE_RPC"
export PRIVATE_KEY="your_wallet_private_key"

cast send $WORMHOLE_ADDRESS "publishMessage(uint32,bytes,uint8)" \
  1 0x48656c6c6f 1 \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Note the transaction hash

# Wait 15 seconds for guardian to observe and sign

# Fetch VAA (use YOUR wallet address, padded to 32 bytes)
# Example: 0xC60B683D1835B72A1f3CdAE3ac29b49607F0176D
# Padded: 000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d

curl "http://localhost:3000/api/v1/vaas/6/000000000000000000000000YOUR_WALLET_ADDRESS/0"
```

---

## Multi-Node Setup (Production)

For production, deploy 3 or more guardian nodes across different VMs.

### Architecture

```
VM-0 (10.0.0.10)                    VM-1 (10.0.0.11)        VM-2 (10.0.0.12)
├── Anvil (registry)                ├── Guardian-1          └── Guardian-2
├── Guardian-0 (bootstrap)          └── (connects to VM-0)      (connects to VM-0)
└── API Server
```

### VM-0: Bootstrap Node Setup

Follow Steps 1-11 from Single Node Setup, then:

```bash
# After starting guardian, get the peer ID
grep "P2P node identity" logs/guardian-0.log
# Output: P2P node identity: 12D3KooWxxxxxxxxxxxxxxxxxxxxxxxxx

# Note this peer ID for VM-1 and VM-2
```

### VM-1: Guardian-1 Setup

```bash
# SSH into VM-1
ssh azureuser@10.0.0.11

# Follow Steps 1-5 from Single Node Setup
# Then configure:
nano config/guardian.conf
```

```bash
# guardian.conf for VM-1
GUARDIAN_INDEX=1
NUM_GUARDIANS=3

# Connect to Anvil on VM-0
GETH_RPC="ws://10.0.0.10:8545"
GETH_CONTRACT="0x_SAME_AS_VM0"

# Same Avalanche contract
AVALANCHE_RPC="ws://YOUR_AVALANCHE_NODE/ws"
AVALANCHE_CONTRACT="0x_SAME_AS_VM0"

# Bootstrap to guardian-0
BOOTSTRAP_PEERS="/ip4/10.0.0.10/udp/8999/quic-v1/p2p/12D3KooWxxxxxxxxx"

UNSAFE_DEV_MODE=true
```

```bash
# Set hostname and start
sudo hostname guardian-1
bin/guardian start
```

### VM-2: Guardian-2 Setup

Same as VM-1, but with:
- `GUARDIAN_INDEX=2`
- `sudo hostname guardian-2`

### Update Contracts with All Guardians

When deploying for production with multiple guardians, deploy contracts with ALL guardian addresses:

```bash
# All 3 guardian addresses (devnet mode)
GUARDIANS="0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe,0x88D7D8B32a9105d228100E72dFFe2Fae0705D31c,0x58076F561CC62A47087B567C86f986426dFCD000"

# Deploy to Anvil
bin/deploy anvil "$GUARDIANS"

# Deploy to Avalanche
export PRIVATE_KEY="deployer_key"
export AVALANCHE_RPC_HTTP="http://avalanche-rpc"
bin/deploy avalanche "$GUARDIANS"
```

### Verify Multi-Node Network

On each VM:
```bash
bin/guardian status
```

Check peer connections:
```bash
grep -i "peer" logs/guardian-X.log | tail -20
```

---

## Systemd Services

For production, use systemd to manage services.

### Install Guardian Service

```bash
# Edit paths in service file
sudo nano /etc/systemd/system/guardian.service
```

```ini
[Unit]
Description=Wormhole Guardian Node
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=azureuser
Group=azureuser
WorkingDirectory=/home/azureuser/projects/Private-Guardian-Network
ExecStart=/home/azureuser/projects/Private-Guardian-Network/bin/guardian start --foreground
Restart=always
RestartSec=10

# Hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/azureuser/projects/Private-Guardian-Network/data
ReadWritePaths=/home/azureuser/projects/Private-Guardian-Network/logs

[Install]
WantedBy=multi-user.target
```

```bash
# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable guardian
sudo systemctl start guardian

# Check status
sudo systemctl status guardian
sudo journalctl -u guardian -f
```

### Install Anvil Service (VM-0 only)

```bash
sudo nano /etc/systemd/system/anvil.service
```

```ini
[Unit]
Description=Anvil Local Ethereum Node
After=network.target

[Service]
Type=simple
User=azureuser
Group=azureuser
WorkingDirectory=/home/azureuser/projects/Private-Guardian-Network
ExecStart=/home/azureuser/.foundry/bin/anvil --host 0.0.0.0 --port 8545 --chain-id 31337 --block-time 1 --state /home/azureuser/projects/Private-Guardian-Network/data/anvil-state.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable anvil
sudo systemctl start anvil
```

### Install API Service (VM-0 only)

```bash
sudo nano /etc/systemd/system/guardian-api.service
```

```ini
[Unit]
Description=Guardian Network API Server
After=network.target guardian.service

[Service]
Type=simple
User=azureuser
Group=azureuser
WorkingDirectory=/home/azureuser/projects/Private-Guardian-Network
ExecStart=/usr/bin/node /home/azureuser/projects/Private-Guardian-Network/src/api/server.js
Environment=PORT=3000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

---

## Log Rotation

Logs are stored in `logs/` directory. Configure logrotate:

```bash
# Update paths in the config
sudo nano /etc/logrotate.d/guardian-network
```

```
/home/azureuser/projects/Private-Guardian-Network/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 azureuser azureuser
    postrotate
        # Signal guardian to reopen log files (if supported)
        kill -HUP $(cat /home/azureuser/projects/Private-Guardian-Network/data/guardian-0.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
```

```bash
# Test configuration
sudo logrotate -d /etc/logrotate.d/guardian-network

# Force rotation
sudo logrotate -f /etc/logrotate.d/guardian-network
```

---

## Firewall Rules

### Azure Network Security Group

Open these ports between VMs:

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 8545 | TCP | Inbound | Anvil RPC |
| 8999 | UDP | Inbound | Guardian P2P (QUIC) |
| 7000 | TCP | Inbound | Guardian gRPC |
| 6600 | TCP | Inbound | Guardian metrics |
| 3000 | TCP | Inbound | API server |

### UFW Configuration

```bash
# Allow from specific IPs (other guardians)
sudo ufw allow from 10.0.0.10 to any port 8545,8999,7000,6600 proto tcp
sudo ufw allow from 10.0.0.10 to any port 8999 proto udp

# Or allow from subnet
sudo ufw allow from 10.0.0.0/24

# Enable firewall
sudo ufw enable
```

---

## Monitoring

### Prometheus Metrics

Guardian exposes metrics at `http://localhost:6600/metrics`

Example Prometheus scrape config:
```yaml
scrape_configs:
  - job_name: 'guardian'
    static_configs:
      - targets:
        - '10.0.0.10:6600'
        - '10.0.0.11:6600'
        - '10.0.0.12:6600'
```

### Health Checks

```bash
# API health
curl http://localhost:3000/health

# Guardian status
curl http://localhost:6600/metrics | grep wormhole

# Anvil connectivity
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}'
```

### Alerting

Set up alerts for:
- Guardian process not running
- High memory usage (>80%)
- P2P peer count below threshold
- VAA signing failures

---

## Backup & Recovery

### What to Backup

| File/Directory | Priority | Description |
|----------------|----------|-------------|
| `keys/guardian-X.key` | **Critical** | Guardian signing key |
| `keys/node-X.key` | High | P2P identity key |
| `config/guardian.conf` | High | Configuration |
| `data/anvil-state.json` | Medium | Anvil blockchain state |
| `data/guardian-X/` | Low | Can be rebuilt |

### Backup Commands

```bash
# Backup critical files
tar -czvf guardian-backup-$(date +%Y%m%d).tar.gz \
  keys/ \
  config/guardian.conf \
  data/anvil-state.json

# Copy to secure location
scp guardian-backup-*.tar.gz backup-server:/backups/
```

### Recovery

```bash
# Stop services
bin/guardian stop
bin/anvil stop

# Restore backup
tar -xzvf guardian-backup-YYYYMMDD.tar.gz

# Start services
bin/anvil start
bin/guardian start
```

---

## Quorum Requirements

| Guardians | Required Signatures | Fault Tolerance |
|-----------|---------------------|-----------------|
| 1 | 1 | 0 |
| 3 | 3 | 0 |
| 5 | 4 | 1 |
| 7 | 5 | 2 |
| 9 | 7 | 2 |
| 13 | 9 | 4 |
| 19 | 13 | 6 |

Formula: `floor(2/3 * n) + 1`

---

## Troubleshooting

### Guardian Won't Start

1. **Check hostname**
   ```bash
   hostname  # Should be guardian-X
   sudo hostname guardian-0
   ```

2. **Check Anvil connectivity**
   ```bash
   curl http://localhost:8545
   ```

3. **Check logs**
   ```bash
   bin/guardian logs
   ```

### No P2P Connections

1. **Verify firewall allows UDP 8999**
2. **Check bootstrap peer format**
   ```
   /ip4/<IP>/udp/8999/quic-v1/p2p/<PEER_ID>
   ```
3. **Get peer ID from guardian-0 logs**
   ```bash
   grep "P2P node identity" logs/guardian-0.log
   ```

### VAAs Not Being Created

1. **Check all guardians are running**
2. **Verify quorum (need all for 3 guardians)**
3. **Check chain connections in logs**
4. **Verify contract addresses match across all guardians**

---

## Next Steps

After successful setup:

1. **Monitor logs** for errors
2. **Set up alerting** for downtime
3. **Configure backups** for keys
4. **Test failover** by stopping one guardian
5. **Document your specific configuration**
