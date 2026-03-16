# Private Guardian Network

A private Wormhole guardian network for cross-chain message verification between **Avalanche L1**, **Solana**, and a local **Anvil** EVM chain.

## Architecture

```
┌──────────────┐       ┌──────────────┐       ┌──────────────┐
│  Guardian-0   │◄─────►│  Guardian-1   │◄─────►│  Guardian-2   │
│  (bootstrap)  │  P2P  │              │  P2P  │              │
└──────┬───────┘       └──────┬───────┘       └──────┬───────┘
       │                      │                      │
       ▼                      ▼                      ▼
  ┌─────────┐  ┌───────────────┐  ┌─────────────┐
  │  Anvil   │  │  Avalanche L1  │  │   Solana     │
  │ (local)  │  │  (Subnet RPC)  │  │  (Validator) │
  └─────────┘  └───────────────┘  └─────────────┘
```

**How it works:**
1. A smart contract on Avalanche (or Solana) emits a Wormhole message via `publishMessage`.
2. All three guardians observe the event through their respective chain watchers.
3. Each guardian signs the observation and gossips it to peers via libp2p.
4. Once 2-of-3 signatures are collected (quorum), a **VAA** (Verified Action Approval) is produced.
5. The VAA can be fetched via the guardian's gRPC API and posted to a target chain.

## Directory Layout

```
<project-root>/                         ← e.g. ~/Private-Guardian-Network
├── configs/                            ← per-guardian configuration
│   ├── guardian-0.conf
│   ├── guardian-1.conf
│   └── guardian-2.conf
├── contracts/                          ← compiled Wormhole contract artifacts
│   ├── evm/                            ← Implementation, Setup, Wormhole bytecode + ABI
│   └── solana/                         ← bridge.so, token_bridge.so
├── docker/                             ← optional containerised setup
├── scripts/                            ← all operational scripts
│   ├── common.sh                       ← shared utilities (sourced by all scripts)
│   ├── start-guardian.sh / stop-guardian.sh
│   ├── start-anvil.sh   / stop-anvil.sh
│   ├── deploy-evm.sh                  ← deploy Wormhole to Anvil or Avalanche
│   ├── deploy-solana.sh               ← deploy + init Wormhole on Solana
│   ├── install-deps.sh                ← install Foundry, wasmvm, grpcurl, Solana CLI
│   └── upgrade.sh                     ← backup → pull → build → verify
├── Makefile
└── README.md

<sibling>/wormhole/                     ← cloned Wormhole repository (../wormhole)
├── node/                               ← guardiand source (Go)
├── proto/                              ← gRPC proto definitions
│   ├── publicrpc/v1/publicrpc.proto    ← VAA fetch / heartbeats / guardian set API
│   ├── gossip/v1/gossip.proto          ← P2P gossip messages
│   ├── node/v1/node.proto              ← admin interface
│   ├── spy/v1/spy.proto                ← spy service
│   └── google/api/                     ← Google API protos (annotations, http)
│       ├── annotations.proto           ← required by publicrpc.proto
│       └── http.proto                  ← HTTP/gRPC transcoding definitions
├── solana/                             ← Solana programs + init scripts
└── build/bin/guardiand                 ← compiled binary (after build)

/solana/wormhole/                       ← runtime storage (BASE_DIR in configs)
├── data/                               ← guardian databases, Anvil state
├── logs/                               ← all log files
├── keys/                               ← guardian & node keys (auto-generated in devMode)
├── pids/                               ← PID files for all processes
├── sockets/                            ← admin + gRPC unix sockets
├── backups/                            ← upgrade backups
├── contracts/solana/                   ← deployed program keypair + ID
└── .foundry/                           ← Foundry cache & data (not ~/.foundry)
```

All growing/runtime data lives under `BASE_DIR` (default `/solana/wormhole`). Change `BASE_DIR` in each config to relocate everything.

## Prerequisites

| Tool | Purpose | Version |
|------|---------|---------|
| **Go** | Build guardiand | 1.21+ |
| **Git** | Clone wormhole repo | any |
| **Foundry** | Anvil + Cast (EVM tools) | latest |
| **Solana CLI** | Deploy Solana programs | stable |
| **grpcurl** | Query guardian gRPC API | latest |
| **jq** | JSON processing | any |
| **Node.js** | Solana init scripts (npx/tsx) | 18+ |

---

## Complete Setup Guide

### Step 1 — Clone the Wormhole Repository

The guardian binary (`guardiand`) is built from the official Wormhole source. Clone it as a **sibling** directory named `wormhole`:

```bash
# From the parent directory of Private-Guardian-Network
cd ~/   # or wherever your projects live
git clone https://github.com/<your-org>/wormhole.git wormhole
```

> **Important:** The directory must be named `wormhole` (not `WormHole-Official-GitHub-Repo`). All configs reference `../wormhole/build/bin/guardiand`.

If you already have it under a different name, rename it:
```bash
mv WormHole-Official-GitHub-Repo wormhole
```

After cloning, you should have:
```
~/
├── Private-Guardian-Network/
└── wormhole/
```

### Step 2 — Install the Proto Dependencies (google/api)

The `wormhole/proto/` directory contains the gRPC service definitions that the guardian exposes. The key files are:

| Proto File | Purpose |
|-----------|---------|
| `publicrpc/v1/publicrpc.proto` | **VAA fetch API** — `GetSignedVAA`, `GetLastHeartbeats`, `GetCurrentGuardianSet` |
| `gossip/v1/gossip.proto` | P2P gossip messages (heartbeats, observations) |
| `node/v1/node.proto` | Admin interface (inject governance VAAs) |
| `google/api/annotations.proto` | HTTP/gRPC transcoding annotations (imported by publicrpc.proto) |
| `google/api/http.proto` | HTTP rule definitions (imported by annotations.proto) |

The `google/api/` protos are **already included** in `wormhole/proto/google/api/`. They are required because `publicrpc.proto` imports them:
```protobuf
import "google/api/annotations.proto";
```

**Verify they exist:**
```bash
ls wormhole/proto/google/api/
# Should show: annotations.proto  http.proto
```

If for any reason they are missing, download them:
```bash
mkdir -p wormhole/proto/google/api
curl -o wormhole/proto/google/api/annotations.proto \
  https://raw.githubusercontent.com/googleapis/googleapis/master/google/api/annotations.proto
curl -o wormhole/proto/google/api/http.proto \
  https://raw.githubusercontent.com/googleapis/googleapis/master/google/api/http.proto
```

These protos are used when querying the guardian gRPC API with `grpcurl` (see [Fetching VAAs](#fetching-vaas) below).

### Step 3 — Install Dependencies

```bash
cd ~/Private-Guardian-Network
make install-deps       # installs Foundry, libwasmvm, grpcurl, Solana CLI
source ~/.bashrc        # reload PATH + Foundry env vars
```

Or install individually:
```bash
./scripts/install-deps.sh foundry
./scripts/install-deps.sh wasmvm
./scripts/install-deps.sh grpcurl
./scripts/install-deps.sh solana
```

Verify:
```bash
anvil --version
cast --version
grpcurl --version
solana --version
```

### Step 4 — Build guardiand

```bash
cd ~/wormhole/node
go build -o ../build/bin/guardiand .
chmod +x ../build/bin/guardiand
cd ~/Private-Guardian-Network
```

Verify:
```bash
../wormhole/build/bin/guardiand version
```

### Step 5 — Initialise Storage

```bash
make init
```

This creates all directories under `BASE_DIR` (`/solana/wormhole`): `data/`, `logs/`, `keys/`, `pids/`, `sockets/`, `backups/`, `.foundry/`.

### Step 6 — Start Anvil

```bash
make start-anvil
```

Verify:
```bash
cast chain-id --rpc-url http://127.0.0.1:8545
# Should output: 31337
```

### Step 7 — Deploy Wormhole Contracts

```bash
# Deploy to local Anvil
make deploy-anvil
# → Note the printed address, update GETH_CONTRACT in all configs

# Deploy to Avalanche L1
make deploy-avalanche
# → Update AVALANCHE_CONTRACT in all configs

# Deploy to Solana (generate keypair + deploy + init)
make deploy-solana
# → Update SOLANA_CONTRACT in all configs
```

### Step 8 — Start Guardians

In `unsafeDevMode`, each guardian requires its hostname to match its name:

```bash
# Guardian 0 (bootstrap node — start first)
sudo hostname guardian-0
make start-0

# Wait ~5 seconds for the bootstrap node to start, then:
sudo hostname guardian-1
make start-1

sudo hostname guardian-2
make start-2
```

Or start all sequentially with built-in delays:
```bash
sudo hostname guardian-0
make start-all
```

Or
```bash
cd "/home/vishnu-intain/Documents/Block Chain/Cross Chain/Private-Guardian-Network"

# Start guardian-0 (bootstrap node)
sudo hostnamectl set-hostname guardian-0
make start-0

# Wait ~5 seconds, then start guardian-1
sudo hostnamectl set-hostname guardian-1
make start-1

# Wait ~5 seconds, then start guardian-2
sudo hostnamectl set-hostname guardian-2
make start-2

# Restore your hostname
sudo hostnamectl set-hostname vishnu-prasad-intain

# Verify all running
make status
```

### Step 9 — Verify

```bash
# Show versions + process status
make status

# Check logs
make logs

# Check heartbeats via gRPC
grpcurl -plaintext localhost:7000 publicrpc.v1.PublicRPCService/GetLastHeartbeats
```

---

## Fetching VAAs

Once guardians are running and quorum is reached, fetch signed VAAs via gRPC.

### Using grpcurl with server reflection

If the guardian supports gRPC reflection (default in recent versions):
```bash
grpcurl -plaintext \
  -d '{"message_id":{"emitter_chain":6,"emitter_address":"<hex-address>","sequence":"1"}}' \
  localhost:7000 publicrpc.v1.PublicRPCService/GetSignedVAA
```

### Using grpcurl with proto files

If reflection is not available, point `grpcurl` at the proto definitions in the wormhole repo:
```bash
grpcurl -plaintext \
  -import-path ../wormhole/proto \
  -import-path ../wormhole/proto/google/api \
  -proto publicrpc/v1/publicrpc.proto \
  -d '{"message_id":{"emitter_chain":6,"emitter_address":"<hex-address>","sequence":"1"}}' \
  localhost:7000 publicrpc.v1.PublicRPCService/GetSignedVAA
```

### Available gRPC Methods

| Method | Description |
|--------|-------------|
| `GetSignedVAA` | Fetch a signed VAA by chain, emitter address, and sequence |
| `GetLastHeartbeats` | Get the latest heartbeat from each guardian |
| `GetCurrentGuardianSet` | Get the active guardian set (addresses + index) |

### Check Heartbeats

```bash
grpcurl -plaintext localhost:7000 publicrpc.v1.PublicRPCService/GetLastHeartbeats
```

### Check Guardian Set

```bash
grpcurl -plaintext localhost:7000 publicrpc.v1.PublicRPCService/GetCurrentGuardianSet
```

---

## Configuration

Each guardian has its own config in `configs/guardian-N.conf`. Key settings:

| Variable | Description |
|----------|-------------|
| `BASE_DIR` | Root storage directory (default `/solana/wormhole`) |
| `GUARDIAN_INDEX` | Guardian number (0, 1, 2) |
| `GETH_CONTRACT` | Wormhole contract address on Anvil |
| `AVALANCHE_RPC` | Avalanche L1 WebSocket endpoint |
| `AVALANCHE_CONTRACT` | Wormhole contract address on Avalanche |
| `SOLANA_RPC` | Solana HTTP RPC endpoint |
| `SOLANA_CONTRACT` | Wormhole program ID on Solana |
| `BOOTSTRAP_PEERS` | P2P bootstrap address (empty for guardian-0) |
| `GUARDIAND_BIN` | Path to guardiand binary (default `../wormhole/build/bin/guardiand`) |

All file paths (keys, logs, data, PIDs, sockets) are derived from `BASE_DIR`.

---

## Make Targets

```
Setup:
  make install-deps         Install Foundry, wasmvm, grpcurl, Solana CLI
  make init                 Create storage directories in BASE_DIR

Anvil:
  make start-anvil / stop-anvil

Deploy:
  make deploy-anvil         Deploy Wormhole to Anvil
  make deploy-avalanche     Deploy Wormhole to Avalanche
  make deploy-solana        Deploy & init on Solana

Guardians:
  make start-0 / start-1 / start-2
  make start-all            Start all (sequential with delays)
  make stop-0 / stop-1 / stop-2
  make stop-all             Stop everything

Logs:
  make logs                 Last 30 lines of all guardian logs
  make logs-0 / logs-1 / logs-2 / logs-anvil   (tail -f)

Maintenance:
  make status               Versions + process status + storage usage
  make upgrade              Backup → pull → build → verify
  make upgrade-check        Check for updates
  make backup               Backup configs + binary + keys
  make clean                Wipe data, logs, keys, pids
```

---

## Storage & Disk Usage

### Overview

**All runtime data is stored under `BASE_DIR`** (default: `/solana/wormhole`). Change `BASE_DIR` in config files to relocate everything. **Nothing grows in the OS home directory** after proper setup.

### What Gets Stored

#### 1. **Anvil (Guardian Registry Storage Only)**

**Purpose:** Anvil is **ONLY** used to store:
- Guardian registry contract (guardian addresses)
- Bridge contract addresses (EVM, Avalanche, Solana)
- RPC endpoint configuration

**No transactions are made through Anvil** after initial contract deployment. Guardian nodes only read from Anvil to get registry information.

| Location | Contents | Expected Size | Growth Rate |
|----------|----------|---------------|-------------|
| `data/anvil-state.json` | Contract state (registry + addresses) | **10-50 KB** | **Static** (only changes on redeployment) |
| `.foundry/anvil/tmp/` | Temporary state snapshots | **<1 MB** | **Minimal** (only during deployment) |

**Optimizations:**
- `ANVIL_BLOCK_TIME=0`: On-demand mining (blocks only created during deployment)
- `ANVIL_STATE_INTERVAL=0`: State saved only on shutdown (no periodic saves)
- Symlink `~/.foundry → /solana/wormhole/.foundry`: Redirects all temp files

**Expected total Anvil storage: <100 KB** (after deployment, no growth)

#### 2. **Guardian Nodes (VAA Storage)**

**Purpose:** Guardian nodes store signed VAAs (Verified Action Approvals) in BadgerDB.

| Location | Contents | Expected Size | Growth Rate |
|----------|----------|---------------|-------------|
| `data/guardian-N/db/` | BadgerDB database (signed VAAs) | **1-10 MB per 1000 VAAs** | **~1-5 KB per VAA** |
| `data/guardian-N/` | Other guardian state | **<1 MB** | **Minimal** |

**VAA Size:** Each VAA is typically **1-5 KB** (depends on payload size).

**Growth Calculation:**
- **Low activity:** 10 VAAs/day = ~50 KB/day = **~18 MB/year**
- **Medium activity:** 100 VAAs/day = ~500 KB/day = **~180 MB/year**
- **High activity:** 1000 VAAs/day = ~5 MB/day = **~1.8 GB/year**

**VAA Purge:** Configure `VAA_PURGE_ENABLED=true` and `VAA_PURGE_RETENTION_DAYS=30` in config to auto-delete old VAAs.

#### 3. **Logs**

| Location | Contents | Expected Size | Growth Rate |
|----------|----------|---------------|-------------|
| `logs/guardian-N.log` | Guardian node logs | **100 MB per file** | **~10-50 MB/day** (depends on log level) |
| `logs/anvil.log` | Anvil logs | **<10 MB** | **Minimal** |

**Log Rotation:** Configured via `LOG_MAX_SIZE` (default: 100M) and `LOG_MAX_FILES` (default: 5) in config files. Logrotate also runs daily (keeps 7 days).

**Expected total log storage: 500-700 MB** (with rotation)

#### 4. **Other Storage**

| Location | Contents | Expected Size |
|----------|----------|---------------|
| `keys/` | Guardian keys, node keys | **<10 KB total** |
| `pids/` | Process ID files | **<1 KB** |
| `sockets/` | Unix domain sockets | **0 bytes** (in-memory) |
| `backups/` | Upgrade backups | **~50 MB each** (last 5 kept) |
| `.foundry/cache/` | Foundry compilation cache | **<10 MB** |
| `.foundry/data/` | Foundry data | **<1 MB** |
| `contracts/evm/` | Contract bytecode | **<1 MB** |
| `contracts/solana/` | Solana programs | **<2 MB** |

### Total Storage Estimate

**Minimal setup (no VAA activity):**
- Anvil: 100 KB
- Guardian nodes (3x): 3 MB (empty databases)
- Logs (rotated): 500 MB
- Other: 10 MB
- **Total: ~500 MB**

**Production setup (100 VAAs/day, 1 year):**
- Anvil: 100 KB
- Guardian nodes (3x): 3 × 180 MB = 540 MB
- Logs (rotated): 500 MB
- Other: 10 MB
- **Total: ~1 GB**

**High activity (1000 VAAs/day, 1 year):**
- Anvil: 100 KB
- Guardian nodes (3x): 3 × 1.8 GB = 5.4 GB
- Logs (rotated): 500 MB
- Other: 10 MB
- **Total: ~6 GB**

### Configurable Storage Paths

All storage paths are configurable in `configs/guardian-N.conf`:

```bash
BASE_DIR="/solana/wormhole"                    # Base directory (change this to relocate everything)

# Anvil storage
ANVIL_STATE_FILE="${BASE_DIR}/data/anvil-state.json"
ANVIL_LOG_FILE="${BASE_DIR}/logs/anvil.log"
ANVIL_PID_FILE="${BASE_DIR}/pids/anvil.pid"

# Guardian storage
DATA_DIR="${BASE_DIR}/data/${GUARDIAN_NAME}"   # BadgerDB location
LOG_FILE="${BASE_DIR}/logs/${GUARDIAN_NAME}.log"
PID_FILE="${BASE_DIR}/pids/${GUARDIAN_NAME}.pid"
KEY_FILE="${BASE_DIR}/keys/${GUARDIAN_NAME}.key"

# Log rotation
LOG_MAX_SIZE="100M"                            # Rotate at 100MB
LOG_MAX_FILES=5                                # Keep 5 rotated files
LOG_COMPRESS=true                               # Compress old logs

# VAA database
VAA_DB_DIR="${DATA_DIR}/db"                    # BadgerDB location
VAA_PURGE_ENABLED=false                        # Auto-purge old VAAs
VAA_PURGE_RETENTION_DAYS=30                    # Keep VAAs for 30 days

# Foundry (redirected via symlink)
FOUNDRY_CACHE_DIR="${BASE_DIR}/.foundry/cache"
FOUNDRY_DATA_DIR="${BASE_DIR}/.foundry/data"
```

### Preventing Home Directory Growth

**Problem:** Anvil creates temporary files in `~/.foundry/anvil/tmp/` by default.

**Solution:** The `start-anvil.sh` script automatically creates a symlink `~/.foundry → /solana/wormhole/.foundry` to redirect all writes.

**If you see `~/.foundry` growing large:**
```bash
make stop-anvil
make clean-foundry    # Migrates existing data and creates symlink
make start-anvil
```

### Log Rotation

**Automatic log rotation** is configured in two ways:

1. **Script-level:** `start-guardian.sh` rotates logs when they exceed `LOG_MAX_SIZE`
2. **System-level:** `systemd/logrotate.conf` runs daily (keeps 7 days, compresses)

**Install logrotate:**
```bash
sudo cp systemd/logrotate.conf /etc/logrotate.d/wormhole-guardian
sudo systemctl restart logrotate
```

### Monitoring Storage

```bash
# Check total storage
du -sh /solana/wormhole

# Check breakdown
du -h --max-depth=1 /solana/wormhole | sort -hr

# Check VAA database size
du -sh /solana/wormhole/data/guardian-*/db

# Check log sizes
du -sh /solana/wormhole/logs/*
```

---

## Systemd Services (Auto-Restart)

For production, use systemd to auto-restart services on failure or reboot.

### Install Services

```bash
# Copy service files
sudo cp systemd/anvil.service /etc/systemd/system/
sudo cp systemd/guardian@.service /etc/systemd/system/

# Install log rotation (optional but recommended)
sudo cp systemd/logrotate.conf /etc/logrotate.d/wormhole-guardian

# Reload systemd
sudo systemctl daemon-reload

# Enable and start Anvil
sudo systemctl enable anvil.service
sudo systemctl start anvil.service

# Enable and start guardians
sudo systemctl enable guardian@guardian-0.service
sudo systemctl start guardian@guardian-0.service

sudo systemctl enable guardian@guardian-1.service
sudo systemctl start guardian@guardian-1.service

sudo systemctl enable guardian@guardian-2.service
sudo systemctl start guardian@guardian-2.service
```

### Manage Services

```bash
# Check status
sudo systemctl status guardian@guardian-0.service
sudo systemctl status anvil.service

# View logs
sudo journalctl -u guardian@guardian-0.service -f
sudo journalctl -u anvil.service -f

# Restart
sudo systemctl restart guardian@guardian-0.service

# Stop
sudo systemctl stop guardian@guardian-0.service
```

> **Note:** When using systemd, do not use `make start-*` / `make stop-*` — use `systemctl` commands instead. The hostname must already be set correctly before the service starts.

---

## Upgrading

```bash
make upgrade-check          # check for updates
make upgrade                # backup → stop → pull → build → verify
./scripts/upgrade.sh rollback /solana/wormhole/backups/<timestamp>   # rollback
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `libwasmvm.x86_64.so not found` | `./scripts/install-deps.sh wasmvm` |
| `Hostname must be guardian-N` | `sudo hostname guardian-N` before starting |
| Guardian fails to start | `make logs-N` to check errors |
| Anvil not found | `./scripts/install-deps.sh foundry` and `source ~/.bashrc` |
| `~/.foundry` growing large (39GB+) | **Anvil creates temp files in `~/.foundry/anvil/tmp/`**<br>Run: `make clean-foundry` to migrate to `/solana/wormhole/.foundry`<br>The `start-anvil.sh` script now auto-creates a symlink, but if you have an existing large directory, run `make clean-foundry` first. |
| grpcurl: `unknown service` | Use proto files: `-import-path ../wormhole/proto -proto publicrpc/v1/publicrpc.proto` |
