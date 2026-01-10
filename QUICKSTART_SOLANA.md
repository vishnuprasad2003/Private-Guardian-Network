# Quick Start: Solana Deployment & Testing

## Prerequisites Check

```bash
# Check Solana CLI
solana --version

# Check if validator is running
curl http://127.0.0.1:8899 -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}'

# Check if guardian is running
./scripts/status.sh

# Check if API server is running (optional)
curl http://localhost:3000/health
```

## Quick Deployment (5 Steps)

### Step 1: Generate Keypair
```bash
solana-keygen new -o keys/solana-deployer.json
solana airdrop 10 $(solana-keygen pubkey keys/solana-deployer.json) --url http://127.0.0.1:8899
```

### Step 2: Deploy Program
```bash
# First run generates program ID (in correct Solana keypair format)
node scripts/deploy-solana-core.js

# Deploy with generated program ID (use quotes for paths with spaces)
solana program deploy \
  --program-id "contracts/solana/artifacts/program-id.json" \
  "contracts/solana/artifacts/bridge.so" \
  --url http://127.0.0.1:8899

# Initialize (second run)
node scripts/deploy-solana-core.js
```

**Note:** The script will output the exact command with proper quoting. Copy and run that command.

### Step 3: Update Config
Add to `config/guardian.conf`:
```
SOLANA_CONTRACT="<program-id-from-step-2>"
```

### Step 4: Publish Message & Post VAA
```bash
# Publish on Avalanche
export WORMHOLE_ADDRESS="0x4f8270c650d1dd73f5d13eb2464c19e35f85a8d8"
export RPC_URL="http://20.253.174.32:80/ext/bc/2ALtzRYgRpRWnTgjdrMArkMvU6RTpcjs7VWmupqYaPrHDrHLSd/rpc"
export PRIVATE_KEY="476645f88bc9ef81a40a45ef84972b8e71944f1bd7080cf2b0d6efdc60ee43e6"

cast send $WORMHOLE_ADDRESS "publishMessage(uint32,bytes,uint8)" \
  10 0x54657374 1 --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Wait 15 seconds, then post to Solana
sleep 15
node scripts/post-vaa-solana.js 6 000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d <sequence>
```

### Step 5: Verify
The `post-vaa-solana.js` script will automatically verify and display the stored payload!

## Or Use Automated Test

```bash
# Start API server (terminal 1)
node scripts/vaa-api-server.js

# Run test (terminal 2)
node scripts/test-solana-e2e.js "Hello Solana!"
```

