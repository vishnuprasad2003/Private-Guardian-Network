# Private Guardian Network

A production-grade private Wormhole guardian network for secure cross-chain messaging between Avalanche L1 and Solana.

## What is This?

This is a **private implementation** of the Wormhole guardian network that allows you to:
- Bridge messages between custom/private blockchains
- Control your own guardian set (trust assumptions)
- Operate independently from the public Wormhole network
- Test cross-chain applications in isolation

## Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | This file - Quick start guide |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | **How it works** - Detailed architecture |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Multi-VM production deployment |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues and solutions |

---

## Quick Start (Single Node)

### Prerequisites

- Ubuntu 22.04 LTS
- 4GB RAM, 2 CPU cores minimum
- Internet access

### Step 1: Install Dependencies

```bash
git clone <repo-url> Private-Guardian-Network
cd Private-Guardian-Network

# Install all dependencies (Go, Node.js, Foundry, etc.)
./scripts/setup/install-deps.sh

# IMPORTANT: Reload shell
source ~/.bashrc
```

### Step 2: Build Guardian

```bash
# Clone Wormhole repository
git clone https://github.com/wormhole-foundation/wormhole.git ../WormHole-Official-GitHub-Repo

# Build guardiand
cd ../WormHole-Official-GitHub-Repo/node
go build -o ../build/bin/guardiand .
cd -

# Install Node.js packages
npm install
```

### Step 3: Configure

```bash
cp config/guardian.conf.example config/guardian.conf
nano config/guardian.conf
```

Key settings:
```bash
GUARDIAN_INDEX=0
NUM_GUARDIANS=1
AVALANCHE_RPC="ws://YOUR_AVALANCHE_NODE/ws"
UNSAFE_DEV_MODE=true
```

### Step 4: Start Services

```bash
# 1. Start Anvil (local Ethereum for guardian registry)
bin/anvil start

# 2. Deploy contracts to Anvil
bin/deploy anvil

# 3. Update config with contract address
# Edit config/guardian.conf: GETH_CONTRACT="0x..."

# 4. Deploy to Avalanche (optional)
export PRIVATE_KEY="your_deployer_key"
export AVALANCHE_RPC_HTTP="http://your-avalanche-rpc"
bin/deploy avalanche
# Edit config/guardian.conf: AVALANCHE_CONTRACT="0x..."

# 5. Deploy to Solana (optional)
# 5a. Start Solana validator (if local)
solana-test-validator --reset
solana airdrop 10 $(solana address) --url http://127.0.0.1:8899

# 5b. Generate program ID
node src/cli/deploy-solana.js generate

# 5c. Deploy program
solana program deploy \
  --program-id contracts/solana/artifacts/program-id.json \
  contracts/solana/artifacts/bridge.so \
  --url http://127.0.0.1:8899

# 5d. Initialize bridge
node src/cli/deploy-solana.js initialize
# Edit config/guardian.conf: SOLANA_CONTRACT="G9TA5QaG3X..."

# 6. Start guardian (hostname required for unsafeDevMode)
sudo hostname guardian-0
bin/guardian start

# 7. Start API server
bin/api start
```

### Step 5: Test

```bash
# Publish a message on Avalanche
cast send $AVALANCHE_CONTRACT "publishMessage(uint32,bytes,uint8)" \
  1 0x48656c6c6f 1 \
  --rpc-url $AVALANCHE_RPC --private-key $PRIVATE_KEY

# Wait 15 seconds, then fetch VAA
curl "http://localhost:3000/api/v1/vaas/6/EMITTER_ADDRESS/SEQUENCE"
```

---

## Architecture Overview

```
┌─────────────────┐     ┌─────────────────────────────────┐     ┌─────────────────┐
│  Avalanche L1   │     │       Guardian Network          │     │     Solana      │
│     Subnet      │     │  ┌──────────┐  ┌──────────┐    │     │    (Optional)   │
│                 │     │  │Guardian 0│◄─►│Guardian 1│    │     │                 │
│  ┌───────────┐  │     │  └────┬─────┘  └─────┬────┘    │     │  ┌───────────┐  │
│  │ Wormhole  │──┼─────┼───────┴──────────────┴─────────┼─────┼──│ Wormhole  │  │
│  │ Contract  │  │     │         ▲                      │     │  │ Program   │  │
│  └───────────┘  │     │    ┌────┴─────┐                │     │  └───────────┘  │
└─────────────────┘     │    │  Anvil   │                │     └─────────────────┘
                        │    │(Registry)│                │
                        │    └──────────┘                │
                        └─────────────────────────────────┘
```

**How it works:**
1. User publishes message on source chain (Avalanche)
2. Guardian observes the `LogMessagePublished` event
3. Guardian signs the message
4. VAA (Verifiable Action Approval) is created
5. VAA can be fetched via API and submitted to target chain

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed explanation.

---

## Directory Structure

```
Private-Guardian-Network/
├── bin/                    # Control scripts
│   ├── anvil               # Local Ethereum node
│   ├── guardian            # Guardian node
│   ├── api                 # REST API server
│   ├── deploy              # Contract deployment
│   └── update              # Update components
├── config/
│   ├── guardian.conf       # Main configuration
│   └── guardian.conf.example
├── contracts/
│   ├── evm/artifacts/      # Compiled EVM contracts
│   └── solana/artifacts/   # Compiled Solana programs
├── data/                   # Runtime data
│   ├── guardian-X/         # Guardian state (BadgerDB)
│   └── anvil-state.json    # Anvil blockchain state
├── docs/                   # Documentation
│   ├── ARCHITECTURE.md     # How it works
│   ├── DEPLOYMENT.md       # Production setup
│   └── TROUBLESHOOTING.md  # Common issues
├── keys/                   # Key storage
│   └── guardian-X.key      # Guardian signing keys
├── logs/                   # Log files
├── scripts/
│   ├── setup/              # VM setup
│   └── deploy/             # Contract deployment
├── src/                    # Node.js source
│   ├── api/                # REST API
│   ├── cli/                # CLI tools
│   └── lib/                # Libraries
└── systemd/                # Service files
```

---

## Commands

### Service Control

```bash
# Anvil (Local Ethereum)
bin/anvil start|stop|restart|status|logs

# Guardian Node
bin/guardian start|stop|restart|status|logs|keygen

# API Server
bin/api start|stop|restart|status|logs
```

### Deployment

```bash
# Deploy to Anvil (local)
bin/deploy anvil

# Deploy to Avalanche
export PRIVATE_KEY="..."
export AVALANCHE_RPC_HTTP="..."
bin/deploy avalanche
```

### Updates

```bash
bin/update version    # Show versions
bin/update anvil      # Update Foundry
bin/update guardian   # Rebuild guardian
bin/update node       # Update npm packages
bin/update all        # Update everything
```

---

## API Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Health check |
| `GET /api/v1/vaas/:chain/:emitter/:seq` | Get VAA |
| `POST /api/v1/vaas/verify` | Verify VAA |
| `GET /api/v1/guardian-set` | Get guardian set |
| `GET /api/v1/chains` | List chains |
| `GET /api/v1/status` | Node status |
| `GET /api/v1/metrics` | Prometheus metrics |

### Example

```bash
# Get VAA
curl http://localhost:3000/api/v1/vaas/6/000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d/0

# Response
{
  "vaa": "01000000000100...",
  "messageId": "6/.../0",
  "parsed": {
    "version": 1,
    "emitterChain": 6,
    "sequence": 0,
    "payload": "48656c6c6f",
    "payloadText": "Hello"
  }
}
```

---

## Configuration

Key settings in `config/guardian.conf`:

| Setting | Description | Example |
|---------|-------------|---------|
| `GUARDIAN_INDEX` | Unique per VM (0, 1, 2...) | `0` |
| `NUM_GUARDIANS` | Total in network | `3` |
| `GETH_RPC` | Anvil WebSocket | `ws://127.0.0.1:8545` |
| `GETH_CONTRACT` | Wormhole on Anvil | `0x...` |
| `AVALANCHE_RPC` | Avalanche WebSocket | `ws://node/ws` |
| `AVALANCHE_CONTRACT` | Wormhole on Avalanche | `0x...` |
| `BOOTSTRAP_PEERS` | P2P bootstrap (empty for guardian-0) | `/ip4/.../p2p/...` |
| `UNSAFE_DEV_MODE` | Required for custom chains | `true` |

---

## Multi-Node Production

For production deployment with multiple guardians:

1. **VM-0**: Anvil + Guardian-0 (bootstrap) + API
2. **VM-1**: Guardian-1
3. **VM-2**: Guardian-2

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for detailed instructions.

### Quorum Requirements

| Guardians | Required Signatures |
|-----------|---------------------|
| 1 | 1 |
| 3 | 3 |
| 5 | 4 |
| 7 | 5 |

---

## File Locations

| Type | Path | Backup Priority |
|------|------|-----------------|
| Guardian keys | `keys/guardian-X.key` | **Critical** |
| Anvil state | `data/anvil-state.json` | **Critical** |
| Config | `config/guardian.conf` | High |
| Guardian data | `data/guardian-X/` | Low (can rebuild) |
| Logs | `logs/` | Low |

---

## Troubleshooting

### "hostname does not appear to be a devnet host"
```bash
sudo hostname guardian-0
```

### VAA not found
1. Check guardian is running: `bin/guardian status`
2. Check logs: `bin/guardian logs -f`
3. Wait 15 seconds after publishing

### Chain ID mismatch
Set `UNSAFE_DEV_MODE=true` in config

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for more.

---

## Security Notes

1. **Guardian Keys**: Store securely, backup encrypted
2. **unsafeDevMode**: Only for private networks with custom chain IDs
3. **Firewall**: Restrict access to guardian ports
4. **Monitoring**: Set up alerts for guardian downtime

---

## License

MIT
