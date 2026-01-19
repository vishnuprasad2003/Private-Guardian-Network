# Private Guardian Network

A production-grade private Wormhole Guardian Network for cross-chain message passing between Avalanche L1 Subnet, Solana, and other EVM chains.

**Pure Bash/Go Implementation**: All scripts use bash/Go - no Node.js dependencies required.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                          PRIVATE GUARDIAN NETWORK                                 │
├──────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌─────────────┐       P2P Network        ┌─────────────┐     ┌─────────────┐  │
│   │ Guardian-0  │◄────────────────────────►│ Guardian-1  │◄───►│ Guardian-2  │  │
│   │ (Bootstrap) │  /wormhole/private/...   │             │     │             │  │
│   │ gRPC: 7000  │                          │ gRPC: 7001  │     │ gRPC: 7002  │  │
│   └──────┬──────┘                          └──────┬──────┘     └──────┬──────┘  │
│          │                                        │                   │          │
│          │ Observe & Sign                         │                   │          │
│          ▼                                        ▼                   ▼          │
│   ┌────────────────────────────────────────────────────────────────────────┐    │
│   │                         WATCHED CHAINS                                  │    │
│   ├────────────────┬────────────────────┬──────────────────────────────────┤    │
│   │     Anvil      │   Avalanche L1     │           Solana                 │    │
│   │   (Registry)   │     (Subnet)       │          (Cluster)               │    │
│   │   127.0.0.1    │  20.253.174.32     │       localhost:8899             │    │
│   │  Chain ID: 2   │   Chain ID: 6      │        Chain ID: 1               │    │
│   └────────────────┴────────────────────┴──────────────────────────────────┘    │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
Private-Guardian-Network/
├── configs/
│   ├── guardian-0.conf        # Bootstrap node configuration
│   ├── guardian-1.conf        # Second guardian configuration
│   └── guardian-2.conf        # Third guardian configuration
├── contracts/
│   ├── evm/                   # Wormhole EVM contract bytecode & ABIs
│   │   ├── Wormhole.json
│   │   ├── Implementation.json
│   │   └── Setup.json
│   └── solana/                # Wormhole Solana program binaries
│       ├── bridge.so
│       └── token_bridge.so
├── scripts/
│   ├── common.sh              # Shared utilities
│   ├── start-guardian.sh      # Start guardian node
│   ├── stop-guardian.sh       # Stop guardian node
│   ├── start-anvil.sh         # Start Anvil (registry)
│   ├── stop-anvil.sh          # Stop Anvil
│   ├── deploy-evm.sh          # Deploy contracts to EVM chains
│   ├── deploy-solana.sh       # Deploy Wormhole to Solana
│   ├── fetch-vaa.sh           # Fetch VAA by message hash
│   └── upgrade.sh             # Upgrade dependencies
├── docker/
│   ├── Dockerfile             # Docker image
│   └── docker-compose.yml     # Docker deployment
├── Makefile                   # Build automation
├── README.md                  # This file
└── .gitignore                 # Git ignore rules
```

**Note**: Runtime directories (`data/`, `logs/`, `keys/`, `backups/`) are gitignored and created automatically.

## Prerequisites

- **OS**: Ubuntu 22.04 LTS or similar Linux distribution
- **Go**: 1.21+ (for building guardiand)
- **Foundry**: cast, anvil (for EVM contract deployment)
- **Docker**: (optional, for containerized deployment)
- **grpcurl**: (for VAA fetching)
- **Solana CLI**: (optional, for Solana contract deployment)

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

# Add to PATH (add to ~/.bashrc for persistence)
export PATH="$HOME/go/bin:$HOME/.foundry/bin:$PATH"
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

In `unsafeDevMode`, guardian keys are **deterministic** based on hostname. These addresses are from the official WormHole repository (`scripts/devnet-consts.json`).

**Source**: `WormHole-Official-GitHub-Repo/scripts/devnet-consts.json`

| Index | Hostname | Guardian Address | P2P Peer ID |
|-------|----------|------------------|-------------|
| 0 | guardian-0 | `0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe` | `12D3KooWL3XJ9EMCyZvmmGXL2LMiVBtrVa2BuESsJiXkSj7333Jw` |
| 1 | guardian-1 | `0x88D7D8B32a9105d228100E72dFFe2Fae0705D31c` | `12D3KooWHHzSeKaY8xuZVzkLbKFfvNgPPeKhFBGrMbNzbm5akpqu` |
| 2 | guardian-2 | `0x58076F561CC62A47087B567C86f986426dFCD000` | `12D3KooWKRyzVWW6ChFjQjK4miCty85Niy49tpPV95XdKu1BcvMA` |
| 3 | guardian-3 | `0xBd6e9833490F8fA87c733A183CD076a6cBD29074` | `12D3KooWB1b3qZxWJanuhtseF3DmPggHCtG36KZ9ixkqHtdKH9fh` |
| 4 | guardian-4 | `0xb853FCF0a5C78C1b56D15fCE7a154e6ebe9ED7a2` | `12D3KooWE4qDcRrueTuRYWUdQZgcy7APZqBngVeXRt4Y6ytHizKV` |
| 5 | guardian-5 | `0xAF3503dBD2E37518ab04D7CE78b630F98b15b78a` | `12D3KooWPgam4TzSVCRa4AbhxQnM9abCYR4E9hV57SN7eAjEYn1j` |
| 6 | guardian-6 | `0x785632deA5609064803B1c8EA8bB2c77a6004Bd1` | `12D3KooWM4yJB31d4hF2F9Vdwuj9WFo1qonoySyw4bVAQ9a9d21o` |
| 7 | guardian-7 | `0x09a281a698C0F5BA31f158585B41F4f33659e54D` | `12D3KooWCv935r3ropYhUe5yMCp9QiUoc9A6cZpYQ5x84DqEPbwb` |
| 8 | guardian-8 | `0x3178443AB76a60E21690DBfB17f7F59F09Ae3Ea1` | `12D3KooWQfG74brcJhzpNwjPCZmcbBv8f6wxKgLSYmEDXXdPXQpH` |
| 9 | guardian-9 | `0x647ec26ae49b14060660504f4DA1c2059E1C5Ab6` | `12D3KooWNEWRB7PnuZs164xaA9QWM3iZHekHyEQo5qGP5KCHHuSN` |
| 10 | guardian-10 | `0x810AC3D8E1258Bd2F004a94Ca0cd4c68Fc1C0611` | `12D3KooWB224kvi7vN34xJfsfW7bnv6eodxTkgo9VFA6UiaGMgRD` |
| 11 | guardian-11 | `0x80610e96d645b12f47ae5cf4546b18538739e90F` | `12D3KooWCR2EoapJjoQVR4E3NLjWn818gG3XizQ92Yx6C424HL2g` |
| 12 | guardian-12 | `0x2edb0D8530E31A218E72B9480202AcBaeB06178d` | `12D3KooWNc5rNmCJ9yvXviXaENnp7vqDQjomZwia4aA7Q3hSYkiW` |
| 13 | guardian-13 | `0xa78858e5e5c4705CdD4B668FFe3Be5bae4867c9D` | `12D3KooWBremnqYWBDK6ctvCuhCqJAps5ZAPADu53gXhQHexrvtP` |
| 14 | guardian-14 | `0x5Efe3A05Efc62D60e1D19fAeB56A80223CDd3472` | `12D3KooWFqdBYPrtwErMosomvD4uRtVhXQdqqZZHC3NCBZYVxr4t` |
| 15 | guardian-15 | `0xD791b7D32C05aBB1cc00b6381FA0c4928f0c56fC` | `12D3KooW9yvKfP5HgVaLnNaxWywo3pLAEypk7wjUcpgKwLznk5gQ` |
| 16 | guardian-16 | `0x14Bc029B8809069093D712A3fd4DfAb31963597e` | `12D3KooWRuYVGEsecrJJhZsSoKf1UNdBVYKFCmFLNj9ucZiSQCYj` |
| 17 | guardian-17 | `0x246Ab29FC6EBeDf2D392a51ab2Dc5C59d0902A03` | `12D3KooWGEcD5sW5osB6LajkHGqiGc3W8eKfYwnJVVqfujkpLWX2` |
| 18 | guardian-18 | `0x132A84dFD920b35a3D0BA5f7A0635dF298F9033e` | `12D3KooWQYz2inBsgiBoqNtmEn1qeRBr9B8cdishFuBgiARcfMcY` |

#### Quorum Requirements

| Guardians | Quorum | Fault Tolerance |
|-----------|--------|-----------------|
| 2 | 2/2 (100%) | 0 nodes can fail |
| 3 | 2/3 (67%) | 1 node can fail |
| 5 | 4/5 (80%) | 1 node can fail |
| 7 | 5/7 (71%) | 2 nodes can fail |
| 13 | 9/13 (69%) | 4 nodes can fail |
| 19 (mainnet) | 13/19 (68%) | 6 nodes can fail |

**Formula**: Quorum = (2/3 × N) + 1 (rounded down)

### Ports

| Service | Guardian-0 | Guardian-1 | Guardian-2 |
|---------|------------|------------|------------|
| P2P | 8999/udp | 8998/udp | 8997/udp |
| gRPC | 7000 | 7001 | 7002 |
| Status | 6600 | 6601 | 6602 |

**Port Pattern for Guardian-N**: P2P = 8999-N, gRPC = 7000+N, Status = 6600+N

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

## Upgrading Dependencies

The upgrade script provides production-grade dependency management with backup, verification, and rollback support.

### Full Upgrade (Recommended)

Upgrade all dependencies while preserving data:

```bash
# Full upgrade with automatic backup
make upgrade

# Or directly:
./scripts/upgrade.sh all
```

This will:
- ✅ Create automatic backup of binaries, configs, keys, and contracts
- ✅ Upgrade Go (if using 'g' version manager)
- ✅ Upgrade Foundry (anvil, cast, forge)
- ✅ Upgrade grpcurl
- ✅ Upgrade Solana CLI tools
- ✅ Upgrade WormHole guardiand binary
- ✅ Upgrade Solana SDK npm dependencies
- ✅ Check for system package updates
- ✅ Verify all upgrades
- ✅ Clean up old backups (keeps last 5)

**Important**: All guardian data, keys, and configurations are preserved. Only binaries and dependencies are updated.

### Selective Upgrades

Upgrade specific components:

```bash
# Check for updates without upgrading
./scripts/upgrade.sh check

# Upgrade only WormHole guardiand
./scripts/upgrade.sh update

# Upgrade only Foundry tools
./scripts/upgrade.sh update-foundry

# Upgrade only Solana CLI
./scripts/upgrade.sh update-solana

# Upgrade only Solana SDK dependencies
./scripts/upgrade.sh update-sdk

# Upgrade to specific WormHole version
./scripts/upgrade.sh tag v2.28.0
```

### Backup & Rollback

```bash
# Create manual backup
make backup

# List available backups
./scripts/upgrade.sh list-backups

# Rollback to specific backup
./scripts/upgrade.sh rollback backups/20260115_120000

# Clean old backups (keep last 5)
./scripts/upgrade.sh cleanup 5
```

### Status & Verification

```bash
# Show current status
make upgrade-status

# Verify installation
./scripts/upgrade.sh verify
```

### Production Best Practices

1. **Always backup before upgrading**:
   ```bash
   make backup
   ```

2. **Test upgrades in staging first** (if available)

3. **Stop guardians before upgrading**:
   ```bash
   make stop
   make upgrade
   make start-0 && make start-1
   ```

4. **Monitor after upgrade**:
   ```bash
   make logs
   # Check guardian health endpoints
   curl http://localhost:6600/metrics
   ```

5. **Keep backups**: The script automatically keeps the last 5 backups

6. **Rollback if needed**: Use the rollback command if issues occur

### What Gets Upgraded

| Component | Command | Data Affected |
|-----------|---------|---------------|
| Go | `update-go` | None (system/version manager) |
| Foundry | `update-foundry` | None |
| grpcurl | `update-grpcurl` | None |
| Solana CLI | `update-solana` | None |
| WormHole guardiand | `update` | Binary only (data preserved) |
| Solana SDK | `update-sdk` | npm packages only |
| System packages | `all` | System packages (optional) |

**All guardian data, keys, configs, and contracts are preserved during upgrades.**

## Notes

- **Keys**: Stored in `keys/` directory (gitignored, never committed)
- **Data**: Stored in `data/` directory (gitignored, guardian database)
- **Logs**: Stored in `logs/` directory (gitignored)
- **Backups**: Created by upgrade script in `backups/` (gitignored)
- **Contracts**: Pre-compiled contract binaries and ABIs included
- **Pure Bash**: All scripts use bash/Go (no Node.js dependencies)

## License

Apache 2.0
