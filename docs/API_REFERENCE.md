# VAA API Server - Complete API Reference

## Base URL
```
http://localhost:3000
```

## Authentication
No authentication required for private network. For production, add authentication middleware.

---

## Endpoints

### VAA Endpoints

#### Get VAA
```http
GET /api/v1/vaas/:chainId/:emitter/:sequence
GET /api/v1/vaas/:messageId
```

**Parameters:**
- `chainId` - Wormhole chain ID (e.g., 6 for Avalanche)
- `emitter` - Emitter address (32-byte hex, with or without 0x prefix)
- `sequence` - Message sequence number
- `messageId` - Format: `chainId/emitter/sequence`

**Response:**
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

**Example:**
```bash
curl http://localhost:3000/api/v1/vaas/6/000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d/1
```

#### Verify VAA
```http
POST /api/v1/vaas/verify
Content-Type: application/json

{
  "vaa": "01000000000100..."
}
```

**Response:**
```json
{
  "valid": true,
  "version": 1,
  "guardianSetIndex": 0,
  "signatureCount": 1,
  "message": "VAA format is valid. Full signature verification requires guardian set lookup."
}
```

---

### Guardian Set Endpoints

#### Get Current Guardian Set
```http
GET /api/v1/guardian-set
```

**Response:**
```json
{
  "index": 0,
  "guardians": [
    "0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe",
    "0x88D7D8B32a9105d228100E72dFFe2Fae0705D31c",
    "0x58076F561CC62A47087B567C86f986426dFCD000"
  ],
  "quorum": 3,
  "total": 3,
  "description": "Requires 3 out of 3 signatures for quorum"
}
```

#### Get Guardian Set by Index
```http
GET /api/v1/guardian-set/:index
```

---

### Chain Information Endpoints

#### List All Chains
```http
GET /api/v1/chains
```

**Response:**
```json
{
  "chains": [
    {"chainId": 1, "name": "Solana", "isTestnet": false},
    {"chainId": 2, "name": "Ethereum", "isTestnet": false},
    ...
  ],
  "total": 30,
  "testnets": 2,
  "mainnets": 28
}
```

#### Get Chain Info
```http
GET /api/v1/chains/:chainId
```

**Response:**
```json
{
  "chainId": 6,
  "name": "Avalanche",
  "isTestnet": false,
  "wormholeChainId": 6
}
```

---

### Message Observation Endpoints

#### Check Message Status
```http
GET /api/v1/messages/:chainId/:emitter/:sequence
```

**Response:**
```json
{
  "messageId": "6/.../1",
  "observed": true,
  "finalized": true,
  "hasVAA": true,
  "vaa": {
    "digest": "...",
    "timestamp": "2026-01-10T22:13:16+05:30"
  },
  "chainId": 6,
  "emitterAddress": "0x...",
  "sequence": 1
}
```

**Use Cases:**
- Check if message is being observed (before VAA is created)
- Verify VAA exists for a message
- Debug message flow issues

---

### Status & Health Endpoints

#### Basic Health Check
```http
GET /health
```

**Response:**
```json
{
  "status": "ok",
  "service": "VAA API Server",
  "guardian": {
    "socket": "/path/to/socket",
    "exists": true
  }
}
```

#### Detailed Health Check
```http
GET /health/detailed
```

**Response:**
```json
{
  "status": "healthy",
  "checks": {
    "apiServer": "ok",
    "guardiandBinary": "ok",
    "guardianSocket": "ok",
    "guardianSet": "ok"
  },
  "guardian": {
    "index": 0,
    "total": 3,
    "quorum": 3
  },
  "timestamp": "2026-01-10T17:09:21.638Z"
}
```

#### Guardian Status
```http
GET /api/v1/status
```

**Response:**
```json
{
  "service": "VAA API Server",
  "status": "operational",
  "guardian": {
    "connected": true,
    "socket": "/path/to/socket",
    "guardianSet": {
      "index": 0,
      "total": 3,
      "quorum": 3
    }
  },
  "timestamp": "2026-01-10T17:09:50.298Z"
}
```

#### Prometheus Metrics
```http
GET /api/v1/metrics
```

**Response:** (Prometheus format)
```
# HELP guardian_set_index Current guardian set index
# TYPE guardian_set_index gauge
guardian_set_index 0

# HELP guardian_set_total Total number of guardians
# TYPE guardian_set_total gauge
guardian_set_total 3

# HELP guardian_set_quorum Required signatures for quorum
# TYPE guardian_set_quorum gauge
guardian_set_quorum 3

# HELP guardian_socket_connected Guardian socket connection status
# TYPE guardian_socket_connected gauge
guardian_socket_connected 1

# HELP api_server_uptime_seconds API server uptime in seconds
# TYPE api_server_uptime_seconds counter
api_server_uptime_seconds 3600
```

---

## Error Responses

All endpoints return standard HTTP status codes:

- `200` - Success
- `400` - Bad Request (invalid parameters)
- `404` - Not Found (VAA/message not found)
- `500` - Internal Server Error

**Error Format:**
```json
{
  "error": "Error message description"
}
```

---

## Use Cases

### Development & Testing
- **Fetch VAAs**: `GET /api/v1/vaas/:chainId/:emitter/:sequence`
- **Check message status**: `GET /api/v1/messages/:chainId/:emitter/:sequence`
- **Verify VAA format**: `POST /api/v1/vaas/verify`

### Production Monitoring
- **Health checks**: `GET /health` or `GET /health/detailed`
- **Metrics**: `GET /api/v1/metrics` (Prometheus)
- **Status monitoring**: `GET /api/v1/status`

### Cross-Chain Application Integration
- **Get VAA for posting**: `GET /api/v1/vaas/:chainId/:emitter/:sequence`
- **Check guardian set**: `GET /api/v1/guardian-set`
- **Chain information**: `GET /api/v1/chains/:chainId`

### Debugging
- **Message observation**: `GET /api/v1/messages/:chainId/:emitter/:sequence`
- **VAA verification**: `POST /api/v1/vaas/verify`
- **Detailed status**: `GET /api/v1/status`

---

## Environment Variables

```bash
PORT=3000                    # API server port
HOST=0.0.0.0                # API server host
DEBUG=true                   # Enable request logging
ALLOWED_ORIGINS=*            # CORS allowed origins (comma-separated)
GUARDIAND_BIN=/path/to/bin   # Path to guardiand binary
ADMIN_SOCKET=/path/to/sock   # Path to admin socket
```

---

## Integration Examples

### JavaScript/TypeScript
```javascript
const baseUrl = 'http://localhost:3000';

// Fetch VAA
const response = await fetch(
  `${baseUrl}/api/v1/vaas/6/000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d/1`
);
const vaa = await response.json();
console.log('VAA:', vaa.vaa);

// Check message status
const status = await fetch(
  `${baseUrl}/api/v1/messages/6/000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d/1`
);
const msgStatus = await status.json();
console.log('Has VAA:', msgStatus.hasVAA);
```

### Python
```python
import requests

base_url = 'http://localhost:3000'

# Fetch VAA
response = requests.get(
    f'{base_url}/api/v1/vaas/6/000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d/1'
)
vaa = response.json()
print(f"VAA: {vaa['vaa']}")
```

### cURL
```bash
# Get VAA
curl http://localhost:3000/api/v1/vaas/6/000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d/1

# Check message status
curl http://localhost:3000/api/v1/messages/6/000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d/1

# Get guardian set
curl http://localhost:3000/api/v1/guardian-set
```

