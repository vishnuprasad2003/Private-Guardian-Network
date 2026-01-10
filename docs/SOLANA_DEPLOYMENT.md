# Solana Wormhole Core Bridge Deployment Guide

This guide covers deploying the Wormhole Core Bridge program to your local Solana validator and testing the complete flow: Avalanche → Guardian → Solana.

## Prerequisites

1. **Solana CLI installed** - [Install Solana CLI](https://docs.solana.com/cli/install-solana-cli-tools)
2. **Local Solana validator running** - `solana-test-validator` or your own validator
3. **Solana keypair** - For deploying and initializing
4. **Guardian node running** - Must be observing Avalanche L1
5. **VAA API server running** (optional, for fetching VAAs)

## Step 1: Generate Solana Keypair

```bash
cd Private-Guardian-Network

# Generate deployer keypair
solana-keygen new -o keys/solana-deployer.json

# Fund the account (if using test validator)
solana airdrop 10 $(solana-keygen pubkey keys/solana-deployer.json) --url http://127.0.0.1:8899
```

## Step 2: Deploy Solana Program

### Option A: Using Solana CLI (Recommended)

```bash
# Set Solana config
solana config set --url http://127.0.0.1:8899

# Deploy the program
cd contracts/solana/artifacts

# First run will generate program ID
node ../../../scripts/deploy-solana-core.js

# This will output a program ID and instructions to deploy
# Example output:
# Generated new program ID: 7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU
# solana program deploy --program-id program-id.json bridge.so

# Deploy with the generated program ID
solana program deploy --program-id program-id.json bridge.so

# After deployment, run initialization
node ../../../scripts/deploy-solana-core.js
```

### Option B: Manual Deployment

```bash
# Generate program keypair
solana-keygen new -o contracts/solana/artifacts/program-id.json

# Deploy
solana program deploy \
  --program-id contracts/solana/artifacts/program-id.json \
  contracts/solana/artifacts/bridge.so \
  --url http://127.0.0.1:8899

# Note the program ID from output
```

## Step 3: Initialize Solana Program

The initialization script will:
- Read guardian addresses from `config/guardian.conf`
- Initialize the bridge with guardian set
- Set fee and expiration time

```bash
cd Private-Guardian-Network

# Set environment variables
export SOLANA_RPC="http://127.0.0.1:8899"
export SOLANA_KEYPAIR="keys/solana-deployer.json"
export SOLANA_CONTRACT="<your-program-id>"  # From deployment step

# Initialize
node scripts/deploy-solana-core.js

# Or set guardian set explicitly
export GUARDIAN_SET='["befa429d57cd18b7f8a4d91a2da9ab4af05d0fbe"]'
export FEE=100000
export EXPIRATION_TIME=86400

node scripts/deploy-solana-core.js
```

**Update config:**
After initialization, add to `config/guardian.conf`:
```bash
SOLANA_CONTRACT="<your-program-id>"
```

## Step 4: Test End-to-End Flow

### 4.1 Publish Message on Avalanche

```bash
export WORMHOLE_ADDRESS="0x4f8270c650d1dd73f5d13eb2464c19e35f85a8d8"
export RPC_URL="http://20.253.174.32:80/ext/bc/2ALtzRYgRpRWnTgjdrMArkMvU6RTpcjs7VWmupqYaPrHDrHLSd/rpc"
export PRIVATE_KEY="476645f88bc9ef81a40a45ef84972b8e71944f1bd7080cf2b0d6efdc60ee43e6"

# Publish message
cast send $WORMHOLE_ADDRESS "publishMessage(uint32,bytes,uint8)" \
  5 0x48656c6c6f536f6c616e61 1 \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Note the sequence number from transaction logs
```

### 4.2 Wait for Guardian to Create VAA

Wait ~10-15 seconds for the guardian to observe and create the VAA.

### 4.3 Fetch VAA

```bash
# Using the API
curl http://localhost:3000/api/v1/vaas/6/000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d/<sequence>

# Or using the script
node scripts/fetch-vaa.js 6 000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d <sequence>
```

### 4.4 Post VAA to Solana

```bash
export SOLANA_RPC="http://127.0.0.1:8899"
export SOLANA_KEYPAIR="keys/solana-deployer.json"

# Post VAA (will fetch from API automatically)
node scripts/post-vaa-solana.js 6 000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d <sequence>

# Or post VAA hex directly
node scripts/post-vaa-solana.js 01000000000100...
```

The script will:
1. Fetch VAA from API (if not provided)
2. Parse VAA to verify format
3. Post VAA to Solana (verifies signatures)
4. Verify payload is stored
5. Display stored payload

### 4.5 Verify Payload on Solana

The `post-vaa-solana.js` script automatically verifies the payload. You can also verify manually:

```bash
# Using Solana CLI
solana account <vaa-account-address> --url http://127.0.0.1:8899

# Or check via RPC
curl -X POST http://127.0.0.1:8899 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "getAccountInfo",
    "params": ["<vaa-account-address>"]
  }'
```

## Step 5: Automated End-to-End Test

Run the complete test script:

```bash
# Start VAA API server (in another terminal)
node scripts/vaa-api-server.js

# Run end-to-end test
node scripts/test-solana-e2e.js "Hello Solana!"

# Or with custom payload
node scripts/test-solana-e2e.js "My test message"
```

This script will:
1. ✅ Publish message on Avalanche
2. ✅ Wait for guardian to observe
3. ✅ Fetch VAA from API
4. ✅ Post VAA to Solana
5. ✅ Verify payload is stored

## Troubleshooting

### Program Not Deployed

**Error:** `Program is not deployed`

**Solution:**
```bash
solana program deploy --program-id contracts/solana/artifacts/program-id.json \
  contracts/solana/artifacts/bridge.so \
  --url http://127.0.0.1:8899
```

### Insufficient Balance

**Error:** `Insufficient balance`

**Solution:**
```bash
solana airdrop 10 $(solana-keygen pubkey keys/solana-deployer.json) --url http://127.0.0.1:8899
```

### VAA Not Found

**Error:** `VAA not found`

**Solutions:**
1. Wait longer (guardian may need more time)
2. Check guardian logs: `./scripts/logs.sh`
3. Verify message was published: Check Avalanche transaction
4. Check sequence number is correct

### Signature Verification Failed

**Error:** `PostVAAConsensusFailed` or signature errors

**Solutions:**
1. Verify guardian set matches between Avalanche and Solana
2. Ensure guardian set is initialized correctly on Solana
3. Check that guardian addresses match in both contracts

### Payload Not Stored

**Error:** VAA posted but payload not found

**Solutions:**
1. Verify VAA was posted successfully (check transaction)
2. Use `getPostedVaa` to read the account
3. Check program logs for errors

## Scripts Reference

### `deploy-solana-core.js`
Deploy and initialize Solana Wormhole Core Bridge program.

**Environment Variables:**
- `SOLANA_RPC` - Solana RPC URL (default: http://127.0.0.1:8899)
- `SOLANA_KEYPAIR` - Keypair file path or base58 key
- `GUARDIAN_SET` - JSON array of guardian addresses (optional, reads from config)
- `FEE` - Bridge fee in lamports (default: 100000)
- `EXPIRATION_TIME` - Guardian set expiration in seconds (default: 86400)

### `post-vaa-solana.js`
Post VAA to Solana and verify payload storage.

**Usage:**
```bash
node scripts/post-vaa-solana.js <chainId> <emitter> <sequence>
node scripts/post-vaa-solana.js <vaaHex>
```

**Environment Variables:**
- `SOLANA_RPC` - Solana RPC URL
- `SOLANA_KEYPAIR` - Keypair file path
- `SOLANA_CONTRACT` - Wormhole program ID (or reads from config)
- `API_URL` - VAA API server URL (default: http://localhost:3000)

### `test-solana-e2e.js`
Complete end-to-end test: Avalanche → Guardian → Solana.

**Usage:**
```bash
node scripts/test-solana-e2e.js [payload]
```

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Avalanche  │────▶│   Guardian   │────▶│   Solana    │
│     L1      │     │    Network   │     │  Validator  │
└─────────────┘     └──────────────┘     └─────────────┘
     │                     │                     │
     │ publishMessage      │ observe & sign       │ postVAA
     │                     │                     │
     ▼                     ▼                     ▼
  Message              VAA Created          Payload Stored
```

## Next Steps

After successful deployment and testing:

1. **Deploy Token Bridge** - For token transfers
2. **Set up Monitoring** - Monitor VAA posting success rate
3. **Production Hardening** - Add error handling, retries, monitoring
4. **Multi-Chain** - Add more chains to the bridge

## References

- [Wormhole Solana Documentation](https://docs.wormhole.com/wormhole/explore-wormhole/solana)
- [Solana Program Deployment](https://docs.solana.com/cli/deploy-a-program)
- [Wormhole SDK](https://github.com/wormhole-foundation/wormhole/tree/main/sdk/js)

