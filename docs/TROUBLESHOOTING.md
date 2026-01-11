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

### Error: Custom(13) - PostVAAConsensusFailed (Solana)

**Cause**: Not enough signatures on VAA. The VAA has fewer signatures than required by the Solana contract's guardian set.

**Solution**: Ensure guardian set in Solana contract matches your network:
```bash
# For single guardian testing
export GUARDIAN_SET='["befa429d57cd18b7f8a4d91a2da9ab4af05d0fbe"]'
node src/cli/deploy-solana.js
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
