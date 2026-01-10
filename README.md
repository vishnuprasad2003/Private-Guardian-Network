# Private Guardian Network

Production-grade Wormhole guardian network for cross-chain messaging between Avalanche L1 and Solana.

## Quick Start

```bash
# 1. Generate guardian key
./scripts/keygen.sh

# 2. Edit configuration
nano config/guardian.conf

# 3. Start guardian
./scripts/start.sh
```

## Directory Structure

```
Private-Guardian-Network/
├── config/
│   └── guardian.conf       # Main configuration file
├── contracts/
│   ├── avalanche/          # EVM contract artifacts
│   │   └── artifacts/
│   └── solana/             # Solana program artifacts
│       └── artifacts/
├── keys/                   # Guardian private keys (gitignored)
├── data/                   # Guardian state data
├── logs/                   # Log files (auto-rotated)
├── scripts/
│   ├── keygen.sh          # Generate guardian key
│   ├── start.sh           # Start guardian node
│   ├── stop.sh            # Stop guardian node
│   ├── status.sh          # Check status
│   ├── logs.sh            # View logs
│   ├── setup.sh           # Initial VM setup
│   ├── deploy-geth.sh     # Deploy private Geth
│   └── deploy-contracts.sh # Deploy Wormhole contracts
├── systemd/
│   └── guardian.service   # Systemd service file
└── docs/
    └── DEPLOYMENT.md      # Full deployment guide
```

## Requirements

- Ubuntu 20.04+ or similar Linux
- Go 1.21+ (for building guardiand)
- Foundry (cast CLI)
- 4GB RAM, 20GB disk

## Documentation

- [Full Deployment Guide](docs/DEPLOYMENT.md)

## Configuration

All settings are in `config/guardian.conf`. Key options:

| Setting | Description |
|---------|-------------|
| `GUARDIAN_INDEX` | Unique node identifier (0, 1, 2...) |
| `GETH_RPC` | Private Ethereum WebSocket URL |
| `AVALANCHE_RPC` | Avalanche L1 WebSocket URL |
| `SOLANA_RPC` | Solana HTTP URL |
| `BOOTSTRAP_PEERS` | Guardian-0's P2P address |
| `LOG_MAX_AGE_DAYS` | Log rotation interval |

## Multi-Node Setup

1. Deploy Private Geth on VM 0
2. Deploy Wormhole contracts with all guardian addresses
3. Start Guardian 0 (bootstrap node)
4. Start Guardians 1, 2, ... with bootstrap peer set
5. Deploy Solana bridge with same guardian addresses

See [DEPLOYMENT.md](docs/DEPLOYMENT.md) for detailed steps.

## Security

- Keys stored with 600 permissions
- Private Geth isolated from public network
- Systemd sandboxing enabled
- Log rotation prevents disk exhaustion

## License

Apache 2.0


## VAA API Server

Production-ready REST API server for fetching VAAs, similar to Wormholescan. Includes endpoints for development, debugging, testing, and production monitoring.

### Starting the API Server

```bash
# Start API server (default: http://0.0.0.0:3000)
./scripts/start-api.sh

# Or with custom port/host
./scripts/start-api.sh --port 8080 --host 127.0.0.1

# Or using npm
npm run api

# With environment variables
PORT=8080 HOST=0.0.0.0 DEBUG=true node scripts/vaa-api-server.js
```

### API Endpoints

#### VAA Endpoints

**Get VAA by Chain ID, Emitter, and Sequence**
```bash
GET /api/v1/vaas/:chainId/:emitter/:sequence
```
Example:
```bash
curl http://localhost:3000/api/v1/vaas/6/000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d/1
```

**Get VAA by Message ID**
```bash
GET /api/v1/vaas/:messageId
```
Example:
```bash
curl http://localhost:3000/api/v1/vaas/6/000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d/1
```

**Verify VAA Signature**
```bash
POST /api/v1/vaas/verify
Content-Type: application/json

{
  "vaa": "01000000000100..."
}
```

#### Guardian Set Endpoints

**Get Current Guardian Set**
```bash
GET /api/v1/guardian-set
```
Returns: guardian addresses, quorum size, total guardians

**Get Guardian Set by Index**
```bash
GET /api/v1/guardian-set/:index
```

#### Chain Information

**List All Supported Chains**
```bash
GET /api/v1/chains
```

**Get Chain Information**
```bash
GET /api/v1/chains/:chainId
```
Example:
```bash
curl http://localhost:3000/api/v1/chains/6  # Avalanche
```

#### Message Observation

**Check Message Observation Status**
```bash
GET /api/v1/messages/:chainId/:emitter/:sequence
```
Returns: whether message is observed, finalized, and has VAA

#### Status & Health

**Basic Health Check**
```bash
GET /health
```

**Detailed Health Check**
```bash
GET /health/detailed
```
Returns: comprehensive status of API server, guardian connection, and guardian set

**Guardian Node Status**
```bash
GET /api/v1/status
```

**Prometheus Metrics**
```bash
GET /api/v1/metrics
```
Returns: Prometheus-formatted metrics for monitoring

### Response Format Examples

**VAA Response:**
```json
{
  "id": "6/000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d/1",
  "version": 1,
  "guardianSetIndex": 0,
  "vaa": "01000000000100...",
  "digest": "b24a119af5bf90fdc128cf845f0e8867ac433e0e4301e8cc0dcaf32bd8302e4c",
  "timestamp": "2026-01-10T22:13:16+05:30",
  "signatures": [{"Index": 0, "Signature": "..."}],
  "emitterChain": 6,
  "emitterAddress": "0x000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d",
  "sequence": 1,
  "consistencyLevel": 1,
  "nonce": 2,
  "payload": "V29ybGQ="
}
```

**Guardian Set Response:**
```json
{
  "index": 0,
  "guardians": ["0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe", ...],
  "quorum": 3,
  "total": 3,
  "description": "Requires 3 out of 3 signatures for quorum"
}
```

**Message Status Response:**
```json
{
  "messageId": "6/.../1",
  "observed": true,
  "finalized": true,
  "hasVAA": true,
  "vaa": {
    "digest": "...",
    "timestamp": "2026-01-10T22:13:16+05:30"
  }
}
```

### Production Features

- **CORS Support**: Configure allowed origins via `ALLOWED_ORIGINS` environment variable
- **Request Logging**: Enable with `DEBUG=true` environment variable
- **Prometheus Metrics**: `/api/v1/metrics` endpoint for monitoring
- **Error Handling**: Comprehensive error responses with appropriate HTTP status codes
- **Health Checks**: Multiple health check endpoints for load balancer integration

