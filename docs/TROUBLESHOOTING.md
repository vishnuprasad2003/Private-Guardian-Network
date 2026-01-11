# Troubleshooting Guide

Common issues and solutions for the Private Guardian Network.

## Table of Contents

- [Guardian Node Issues](#guardian-node-issues)
- [VAA Issues](#vaa-issues)
- [Anvil Issues](#anvil-issues)
- [P2P Issues](#p2p-issues)
- [API Server Issues](#api-server-issues)
- [Contract Issues](#contract-issues)
- [Getting Help](#getting-help)

---

## Guardian Node Issues

### Error: "hostname does not appear to be a devnet host"

**Cause**: `unsafeDevMode` requires hostname to be `guardian-X` format.

**Solution**:
```bash
# Set hostname (temporary)
sudo hostname guardian-0

# Or permanently
sudo hostnamectl set-hostname guardian-0

# Verify
hostname

# Then start guardian
bin/guardian start
```

### Error: "refusing to override existing key"

**Cause**: Key file exists from previous run in unsafeDevMode.

**Solution**:
```bash
rm -f keys/guardian-0.key
bin/guardian start
```

### Error: "Please specify --guardianKey"

**Cause**: Not in unsafeDevMode and no key file exists.

**Solution**:
```bash
# Option 1: Enable unsafeDevMode in config
# In config/guardian.conf:
UNSAFE_DEV_MODE=true

# Option 2: Generate a real key
bin/guardian keygen
```

### Error: "failed to verify evm chain id"

**Cause**: Chain ID mismatch between config and actual chain.

**Solution**:
```bash
# Enable unsafeDevMode to bypass chain ID verification
# In config/guardian.conf:
UNSAFE_DEV_MODE=true
```

### Error: "ethRPC not specified"

**Cause**: Ethereum RPC not configured.

**Solution**: Update `config/guardian.conf`:
```bash
# For Anvil (local)
GETH_RPC="ws://127.0.0.1:8545"
GETH_CONTRACT="0x_YOUR_CONTRACT_ADDRESS"
```

### Guardian Crashes Immediately

**Causes & Solutions**:

1. **Check hostname** (for unsafeDevMode):
   ```bash
   hostname  # Should be guardian-0
   ```

2. **Check Anvil is running**:
   ```bash
   bin/anvil status
   curl http://localhost:8545
   ```

3. **Check logs for specific error**:
   ```bash
   bin/guardian logs
   ```

4. **Remove stale PID file**:
   ```bash
   rm -f data/guardian-0.pid
   ```

---

## VAA Issues

### VAA Not Found

**Possible Causes**:
1. Message not yet observed (wait 15 seconds)
2. Guardian set mismatch
3. Wrong emitter address format

**Solutions**:

```bash
# 1. Check guardian is observing messages
bin/guardian logs -f | grep "observation"

# 2. Verify guardian set matches contract
curl http://localhost:3000/api/v1/guardian-set

# 3. Check emitter address format
# Correct (32-byte padded, lowercase):
# 000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d
# 
# Wrong (not padded):
# c60b683d1835b72a1f3cdae3ac29b49607f0176d

# 4. Check sequence number starts from 0
curl "http://localhost:3000/api/v1/vaas/6/EMITTER/0"
```

---

## Solana Issues

### Error: Custom(13) - PostVAAConsensusFailed (Solana)

**Cause**: Not enough signatures on VAA. The VAA has fewer signatures than required by the Solana contract's guardian set.

**Solution**: Ensure guardian set in Solana contract matches your network:
```bash
# Check if bridge is initialized
node src/cli/deploy-solana.js status

# If not initialized, initialize with guardian set
node src/cli/deploy-solana.js initialize

# Verify guardian set matches your network
# The guardian set in Solana must match the guardians that signed the VAA
```

### Error: Account Info is Null (Solana Bridge)

**Cause**: Solana Wormhole bridge program is not deployed or initialized.

**Symptoms:**
```
Error: account info is null
at Object.getAccountData
```

**Solution:**
```bash
# 1. Check if program is deployed
solana program show G9TA5QaG3XutR4LCCGzcfdoP6LB4e2YSp5D98vhN5cea --url http://127.0.0.1:8899

# 2. If not deployed, deploy it
solana program deploy \
  --program-id contracts/solana/artifacts/program-id.json \
  contracts/solana/artifacts/bridge.so \
  --url http://127.0.0.1:8899

# 3. Initialize the bridge
node src/cli/deploy-solana.js initialize

# 4. Verify initialization
node src/cli/deploy-solana.js status
```

### Error: Simulation Failed - Attempt to Debit Account

**Cause**: Solana wallet doesn't have enough SOL to pay transaction fees.

**Solution:**
```bash
# Check balance
solana balance $(solana address) --url http://127.0.0.1:8899

# Airdrop SOL (local validator only)
solana airdrop 10 $(solana address) --url http://127.0.0.1:8899

# For production: Transfer SOL to your wallet
```

### Solana Program Not Found

**Cause**: Program ID doesn't exist or program wasn't deployed.

**Solution:**
```bash
# 1. Generate program ID (if not exists)
node src/cli/deploy-solana.js generate

# 2. Verify program-id.json exists
ls -la contracts/solana/artifacts/program-id.json

# 3. Deploy program
solana program deploy \
  --program-id contracts/solana/artifacts/program-id.json \
  contracts/solana/artifacts/bridge.so \
  --url http://127.0.0.1:8899

# 4. Verify deployment
solana program show $(cat contracts/solana/artifacts/program-id.json | jq -r '.[:32] | @base64d | .[0:32]') --url http://127.0.0.1:8899
```

### Solana Bridge Not Initialized

**Cause**: Program is deployed but not initialized with guardian set.

**Solution:**
```bash
# Check status
node src/cli/deploy-solana.js status

# If shows "Program deployed" but not initialized:
node src/cli/deploy-solana.js initialize

# Verify initialization by checking bridge account
# (The initialize script will show transaction signature)
```

### Posted VAA Not Found on Solana

**Cause**: VAA wasn't posted or posted to wrong program.

**Solution:**
```bash
# 1. Verify VAA exists (fetch from guardian API)
curl "http://localhost:3000/api/v1/vaas/6/EMITTER/SEQUENCE"

# 2. Check VAA has enough signatures (quorum)
# Response should show "signatures": N where N >= quorum

# 3. Post VAA to Solana
# Using Solana-WormHole API:
curl -X POST http://localhost:8855/api/wormhole/vaa/post \
  -H "Content-Type: application/json" \
  -d "{\"vaaBytes\": \"VAA_HEX\"}"

# 4. Verify posted VAA
curl -X POST http://localhost:8855/api/wormhole/posted-vaa/check \
  -H "Content-Type: application/json" \
  -d "{\"vaaBytes\": \"VAA_HEX\"}"
```

### Solana Validator Restart Issues

**Cause**: Local Solana validator was restarted, losing program state.

**Solution:**
```bash
# After restarting validator, redeploy and reinitialize:

# 1. Redeploy program
solana program deploy \
  --program-id contracts/solana/artifacts/program-id.json \
  contracts/solana/artifacts/bridge.so \
  --url http://127.0.0.1:8899

# 2. Reinitialize bridge
node src/cli/deploy-solana.js initialize

# 3. Update config if program ID changed
nano config/guardian.conf
# Set: SOLANA_CONTRACT="NEW_PROGRAM_ID"

# 4. Restart guardian (to pick up new contract)
bin/guardian restart
```

**Note**: For production, use a persistent Solana cluster (mainnet/devnet) to avoid this issue.

### Guardian Not Observing Solana

**Cause**: Guardian not configured to watch Solana or Solana RPC not accessible.

**Solution:**
```bash
# 1. Check config has Solana settings
grep SOLANA config/guardian.conf

# 2. Verify Solana RPC is accessible
curl -X POST http://127.0.0.1:8899 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}'

# 3. Check guardian logs for Solana connection
bin/guardian logs | grep -i solana

# 4. Verify SOLANA_CONTRACT is set correctly
grep SOLANA_CONTRACT config/guardian.conf
```

### VAA Parsing Error on Solana

**Cause**: VAA format incorrect or corrupted.

**Solution:**
```bash
# 1. Verify VAA format
curl -X POST http://localhost:3000/api/v1/vaas/verify \
  -H "Content-Type: application/json" \
  -d "{\"vaaHex\": \"VAA_HEX\"}"

# 2. Check VAA is hex (not base64)
# Should be: 01000000000100...

# 3. Ensure VAA has correct length
# Minimum: ~200 hex characters (100 bytes)

# 4. Verify emitter address is padded to 32 bytes (64 hex chars)
```

### VAA Signed But Not Stored

**Cause**: Guardian observed the message but couldn't verify it against the contract's guardian set.

**Solution**:
1. Check the contract was deployed with the correct guardian address
2. Verify the guardian's address matches what's in the contract:
   ```bash
   cast call $CONTRACT "getGuardianSet(uint32)(address[])" 0 --rpc-url $RPC
   ```

---

## Anvil Issues

### Anvil Not Starting

```bash
# Check if already running
bin/anvil status

# Kill any stuck process
pkill -f "anvil.*8545"

# Start fresh
bin/anvil start
```

### Anvil Not Responding

```bash
# Test connection
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}'

# Restart Anvil
bin/anvil restart
```

### State Not Persisting

Anvil saves state every 60 seconds by default. Check:
```bash
ls -la data/anvil-state.json

# Force state save by restarting
bin/anvil restart
```

### Contracts Gone After Restart

If using `--load-state` without `--state`, contracts won't persist.

**Solution**: Our config uses both `--state` and `--load-state` automatically.

---

## P2P Issues

### No Peer Connections

**Check**:
```bash
# Verify bootstrap peer format is correct
# Format: /ip4/IP/udp/PORT/quic-v1/p2p/PEER_ID

# Correct:
/ip4/10.0.0.10/udp/8999/quic-v1/p2p/12D3KooWxxxxxxxxx

# Wrong (missing peer ID):
/ip4/10.0.0.10/udp/8999/quic
```

**Check firewall**:
```bash
sudo ufw status
# Allow UDP 8999
sudo ufw allow 8999/udp
```

### Bootstrap Peer Not Found

```bash
# On guardian-0, find peer ID
grep "P2P node identity" logs/guardian-0.log

# Example output:
# P2P node identity: 12D3KooWxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Use complete multiaddr on guardian-1, guardian-2:
BOOTSTRAP_PEERS="/ip4/<GUARDIAN_0_IP>/udp/8999/quic-v1/p2p/<PEER_ID>"
```

### Peers Disconnect Frequently

**Check network connectivity**:
```bash
# From guardian-1, test connectivity to guardian-0
nc -uzv 10.0.0.10 8999

# Check for packet loss
ping -c 10 10.0.0.10
```

---

## API Server Issues

### API Not Starting

```bash
# Check Node.js
node --version

# Install packages
npm install

# Check for port conflicts
lsof -i :3000

# Check logs
bin/api logs
```

### Health Check Failing

```bash
curl http://localhost:3000/health

# If no response, restart
bin/api restart
```

### CORS Errors

API includes CORS middleware by default. For production with specific origins:

Edit `src/api/server.js`:
```javascript
app.use(cors({
    origin: ['https://yourdomain.com']
}));
```

---

## Contract Issues

### Deployment Failed

```bash
# Check Anvil is running
bin/anvil status

# Check PRIVATE_KEY is set
echo $PRIVATE_KEY

# Check account balance
cast balance 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url http://localhost:8545
```

### Contract Not Deployed / Wrong Address

```bash
# Check deployment
cast call $CONTRACT "getCurrentGuardianSetIndex()(uint32)" --rpc-url $RPC_URL

# If error, redeploy
bin/deploy anvil "0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe"
```

### Wrong Guardian Set in Contract

```bash
# Check guardian set in contract
cast call $CONTRACT "getGuardianSet(uint32)(address[])" 0 --rpc-url $RPC_URL

# Compare with expected (unsafeDevMode guardian-0):
# 0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe

# If wrong, redeploy with correct addresses
bin/deploy anvil "0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe"
```

---

## Getting Help

### Quick Diagnostics

```bash
# Check all services
bin/anvil status
bin/guardian status
bin/api status

# Check versions
bin/update version

# Check logs
bin/guardian logs
bin/anvil logs
bin/api logs
```

### Debug Mode

For verbose logging:
```bash
# In config/guardian.conf
LOG_LEVEL="debug"

# Restart guardian
bin/guardian restart
```

### Check Metrics

```bash
# Guardian metrics
curl http://localhost:6600/metrics | grep wormhole

# API detailed health
curl http://localhost:3000/health
```

### Verify Configuration

```bash
# Check config is loaded
cat config/guardian.conf | grep -v "^#" | grep -v "^$"

# Verify contract addresses
curl http://localhost:3000/api/v1/status
```

---

## Common Error Codes

| Error | Meaning | Solution |
|-------|---------|----------|
| `hostname does not appear` | Wrong hostname for unsafeDevMode | `sudo hostname guardian-0` |
| `refusing to override` | Key file exists | `rm -f keys/guardian-0.key` |
| `chain id mismatch` | Chain ID verification failed | Enable `UNSAFE_DEV_MODE=true` |
| `VAA not found` | Message not signed yet | Wait 15s, check logs |
| `Custom(13)` | Signature count mismatch | Redeploy with correct guardian count |
| `ethRPC not specified` | Missing Anvil/Geth config | Set `GETH_RPC` in config |
| `connection refused` | Service not running | Start Anvil: `bin/anvil start` |
