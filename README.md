# Private Guardian Network

A production-grade private Wormhole Guardian Network for cross-chain message passing between Avalanche L1 Subnet, Solana, and other EVM chains.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        PRIVATE GUARDIAN NETWORK                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌───────────────┐         P2P Network         ┌───────────────┐          │
│   │  Guardian-0   │◄───────────────────────────►│  Guardian-1   │          │
│   │  (Bootstrap)  │    /wormhole/private/...    │               │          │
│   │  Port: 7000   │                             │  Port: 7001   │          │
│   └───────┬───────┘                             └───────┬───────┘          │
│           │                                             │                   │
│           │ Observe & Sign                              │ Observe & Sign    │
│           ▼                                             ▼                   │
│   ┌───────────────────────────────────────────────────────────────┐        │
│   │                    WATCHED CHAINS                              │        │
│   ├───────────────┬───────────────────┬───────────────────────────┤        │
│   │    Anvil      │   Avalanche L1    │        Solana             │        │
│   │  (Registry)   │    (Subnet)       │       (Cluster)           │        │
│   │  127.0.0.1    │  20.253.174.32    │    20.64.169.42           │        │
│   │  Chain ID: 2  │  Chain ID: 6      │    Chain ID: 1            │        │
│   └───────────────┴───────────────────┴───────────────────────────┘        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
Private-Guardian-Network/
├── configs/
│   ├── guardian-0.conf      # Bootstrap node configuration
│   └── guardian-1.conf      # Additional node configuration
├── contracts/
│   ├── evm/                  # Wormhole EVM contract bytecode
│   └── solana/               # Wormhole Solana program binary
├── scripts/
│   ├── common.sh             # Shared utilities
│   ├── start-guardian.sh     # Start guardian node
│   ├── stop-guardian.sh      # Stop guardian node
│   ├── start-anvil.sh        # Start Anvil (registry)
│   ├── stop-anvil.sh         # Stop Anvil
│   ├── deploy-evm.sh         # Deploy contracts to EVM chains
│   └── deploy-solana.sh      # Deploy Wormhole to Solana
├── docker/
│   └── docker-compose.yml    # Docker deployment
├── data/                     # Runtime data (gitignored)
├── keys/                     # Guardian keys (gitignored)
├── logs/                     # Log files (gitignored)
├── Makefile                  # Build automation
└── README.md
```

## Prerequisites

- Ubuntu 22.04 LTS
- Go 1.21+
- Foundry (cast, anvil)
- Docker (optional)
- grpcurl (for VAA fetching)

### Install Dependencies

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install grpcurl
go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
export PATH="$HOME/go/bin:$PATH"

# Build guardiand (from WormHole-Official-GitHub-Repo)
cd ../WormHole-Official-GitHub-Repo/node
go build -o ../build/bin/guardiand .
```

## Quick Start

### Step 1: Start Anvil (Guardian Registry)

```bash
./scripts/start-anvil.sh
```

### Step 2: Configure Deployer Keys

Edit `configs/guardian-0.conf`:
```bash
# Avalanche deployer key (funded account)
AVALANCHE_DEPLOYER_KEY="your_avalanche_private_key"

# Solana deployer key (faucet keypair)
SOLANA_DEPLOYER_KEY="../Solana-Validator-Node/keys/faucet.json"
```

### Step 3: Deploy Contracts

```bash
# Deploy to Anvil (guardian registry)
make deploy-anvil

# Deploy to Avalanche L1
make deploy-avalanche

# Deploy to Solana (optional)
make deploy-solana
```

### Step 4: Update Contract Addresses

After each deployment, update `configs/guardian-0.conf` and `configs/guardian-1.conf`:
```bash
GETH_CONTRACT="0x..."          # From deploy-anvil output
AVALANCHE_CONTRACT="0x..."     # From deploy-avalanche output
SOLANA_CONTRACT="..."          # From deploy-solana output (Program ID)
```

### Step 5: Start Guardian Nodes

**Terminal 1 - Guardian-0:**
```bash
sudo hostname guardian-0
./scripts/start-guardian.sh configs/guardian-0.conf
```

Note the **Peer ID** from the output.

**Terminal 2 - Guardian-1:**
```bash
# Update configs/guardian-1.conf with BOOTSTRAP_PEERS from guardian-0
# BOOTSTRAP_PEERS="/ip4/127.0.0.1/udp/8999/quic-v1/p2p/<PEER_ID>"

sudo hostname guardian-1
./scripts/start-guardian.sh configs/guardian-1.conf
```

### Step 6: Publish Message & Fetch VAA

```bash
# Publish message to Avalanche
cast send "$AVALANCHE_CONTRACT" \
  "publishMessage(uint32,bytes,uint8)(uint64)" 1 "0x48656c6c6f" 1 \
  --rpc-url "$AVALANCHE_RPC_HTTP" \
  --private-key "$PRIVATE_KEY"

# Get emitter address
EMITTER=$(cast wallet address --private-key "$PRIVATE_KEY" | sed 's/0x//' | tr '[:upper:]' '[:lower:]')

# Fetch VAA (wait ~60s for finality)
grpcurl -plaintext \
  -import-path "../WormHole-Official-GitHub-Repo/proto" \
  -proto publicrpc/v1/publicrpc.proto \
  -d "{\"message_id\": {\"emitter_chain\": 6, \"emitter_address\": \"000000000000000000000000$EMITTER\", \"sequence\": 0}}" \
  localhost:7000 publicrpc.v1.PublicRPCService/GetSignedVAA
```

## Configuration Reference

### Chain Configuration

| Chain | Wormhole ID | RPC | Deployment |
|-------|-------------|-----|------------|
| Anvil (Registry) | 2 | ws://127.0.0.1:8545 | `make deploy-anvil` |
| Avalanche L1 | 6 | ws://20.253.174.32:80/ext/bc/.../ws | `make deploy-avalanche` |
| Solana | 1 | http://20.64.169.42:8899 | `make deploy-solana` |

### Guardian Addresses (unsafeDevMode)

In `unsafeDevMode`, guardian keys are deterministic based on hostname:

| Hostname | Guardian Address |
|----------|------------------|
| guardian-0 | `0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe` |
| guardian-1 | `0x88D7D8B32a9105d228100E72dFFe2Fae0705D31c` |

### Ports

| Service | Guardian-0 | Guardian-1 |
|---------|------------|------------|
| P2P | 8999/udp | 8998/udp |
| gRPC | 7000 | 7001 |
| Status | 6600 | 6601 |

## API Reference

### Fetch VAA

```bash
grpcurl -plaintext \
  -import-path "../WormHole-Official-GitHub-Repo/proto" \
  -proto publicrpc/v1/publicrpc.proto \
  -d '{"message_id": {"emitter_chain": 6, "emitter_address": "000000000000000000000000<address>", "sequence": 0}}' \
  localhost:7000 publicrpc.v1.PublicRPCService/GetSignedVAA
```

### Get Guardian Set

```bash
grpcurl -plaintext \
  -import-path "../WormHole-Official-GitHub-Repo/proto" \
  -proto publicrpc/v1/publicrpc.proto \
  localhost:7000 publicrpc.v1.PublicRPCService/GetCurrentGuardianSet
```

### Get Heartbeats

```bash
grpcurl -plaintext \
  -import-path "../WormHole-Official-GitHub-Repo/proto" \
  -proto publicrpc/v1/publicrpc.proto \
  localhost:7000 publicrpc.v1.PublicRPCService/GetLastHeartbeats
```

## Multi-Node Production Setup

For production with multiple VMs:

### VM-0 (Bootstrap Guardian)
```bash
# configs/guardian-0.conf
GUARDIAN_INDEX=0
ANVIL_HOST="<VM-0-IP>"  # or 127.0.0.1 if Anvil on same VM
BOOTSTRAP_PEERS=""

sudo hostname guardian-0
./scripts/start-guardian.sh configs/guardian-0.conf
```

### VM-1 (Additional Guardian)
```bash
# configs/guardian-1.conf
GUARDIAN_INDEX=1
ANVIL_HOST="<VM-0-IP>"  # Connect to VM-0's Anvil
BOOTSTRAP_PEERS="/ip4/<VM-0-IP>/udp/8999/quic-v1/p2p/<PEER_ID>"

sudo hostname guardian-1
./scripts/start-guardian.sh configs/guardian-1.conf
```

## Troubleshooting

### Hostname Error
```
failed to generate devnet guardian key: hostname X does not appear to be a devnet host
```
**Solution:** Set hostname to `guardian-N` format:
```bash
sudo hostname guardian-0
```

### Permission Denied on Database
```
Cannot write pid file ... permission denied
```
**Solution:** Clean up data directory:
```bash
sudo rm -rf data/guardian-*
```

### Chain ID Mismatch
```
evm chain ID miss match, expected 1, received 31337
```
**Solution:** Ensure `--unsafeDevMode` flag is enabled (bypasses chain ID verification).

### VAA Not Found
- Wait for block finality (~60 seconds for Avalanche)
- Check guardian logs: `grep "found new message" logs/guardian-0.log`
- Verify quorum: `grep "signed VAA" logs/guardian-0.log`

## License

Apache 2.0
