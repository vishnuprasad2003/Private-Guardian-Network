# Avalanche L1 Wormhole Core Bridge Deployment

This guide covers deploying the Wormhole Core Bridge contract to your Avalanche L1 subnet.

## Prerequisites

1. **Foundry installed**
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. **Private key for deployment wallet**
   - Wallet: `0xC60B683D1835B72A1f3CdAE3ac29b49607F0176D`
   - Must have native tokens for gas

3. **Guardian addresses ready**
   - Generated from `keys/guardian-addresses.txt`

## Contract Structure

The Wormhole Core Bridge consists of:
- **Implementation.sol**: Core logic for message verification and VAA parsing
- **Setup.sol**: Initialization contract for guardian set
- **Wormhole.sol**: Proxy contract (entry point)

## Deployment Steps

### Step 1: Get Your L1 Chain ID

```bash
cast chain-id --rpc-url http://20.253.174.32:80/ext/bc/2ALtzRYgRpRWnTgjdrMArkMvU6RTpcjs7VWmupqYaPrHDrHLSd/rpc
```

### Step 2: Prepare Guardian Set

Edit `deploy-config.json` with your guardian Ethereum addresses:

```json
{
  "initialGuardians": [
    "0x<GUARDIAN_0_ADDRESS>",
    "0x<GUARDIAN_1_ADDRESS>",
    "0x<GUARDIAN_2_ADDRESS>"
  ],
  "guardianSetIndex": 0,
  "chainId": 10001,
  "governanceChainId": 10001,
  "governanceContract": "0x0000000000000000000000000000000000000000000000000000000000000004"
}
```

### Step 3: Deploy Using Foundry

```bash
# Set environment variables
export RPC_URL="http://20.253.174.32:80/ext/bc/2ALtzRYgRpRWnTgjdrMArkMvU6RTpcjs7VWmupqYaPrHDrHLSd/rpc"
export PRIVATE_KEY="<YOUR_DEPLOYER_PRIVATE_KEY>"

# Navigate to Wormhole ethereum contracts
cd ../../WormHole-Official-GitHub-Repo/ethereum

# Deploy (use the forge script)
./scripts/deploy-avalanche-l1.sh
```

### Step 4: Verify Deployment

```bash
# Check contract exists
cast code <DEPLOYED_ADDRESS> --rpc-url $RPC_URL

# Query guardian set
cast call <DEPLOYED_ADDRESS> "getCurrentGuardianSetIndex()(uint32)" --rpc-url $RPC_URL
```

### Step 5: Update Configuration

After deployment, update these files:
- `config/environment/production.env`: Set `AVALANCHE_CONTRACT`
- `config/chains/avalanche-l1.yaml`: Set `contracts.core_bridge`

## Alternative: Manual Deployment

If forge scripts don't work, deploy manually:

```bash
# 1. Deploy Implementation
forge create src/Implementation.sol:Implementation \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# 2. Deploy Setup
forge create src/Setup.sol:Setup \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# 3. Deploy Wormhole proxy with initialization
# See deploy-manual.sh for full commands
```

## Publishing Messages

Once deployed, contracts can publish messages:

```solidity
interface IWormhole {
    function publishMessage(
        uint32 nonce,
        bytes memory payload,
        uint8 consistencyLevel
    ) external payable returns (uint64 sequence);
}
```

Example:
```bash
# Publish a test message
cast send <WORMHOLE_ADDRESS> \
  "publishMessage(uint32,bytes,uint8)" \
  1 \
  0x48656c6c6f20576f726d686f6c6521 \
  1 \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

## Contract Addresses

| Contract | Address | Notes |
|----------|---------|-------|
| Core Bridge | `<TO_BE_DEPLOYED>` | Main entry point |
| Implementation | `<TO_BE_DEPLOYED>` | Logic contract |
| Setup | `<TO_BE_DEPLOYED>` | Used once for init |

## Troubleshooting

### "Execution reverted"
- Check guardian addresses are correct
- Ensure wallet has gas tokens

### "Invalid guardian set"
- Verify guardian addresses match your keys
- Check guardian set index is 0 for fresh deployment

### "Connection refused"
- Verify RPC URL is accessible
- Check firewall rules on L1 node

