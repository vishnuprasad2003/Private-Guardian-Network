# EVM Contracts

Pre-compiled Wormhole contracts for EVM chains (Geth, Avalanche, etc.)

## Files

| File | Description |
|------|-------------|
| `Implementation.bytecode` | Core implementation contract |
| `Implementation.abi.json` | Implementation ABI |
| `Setup.bytecode` | Setup contract |
| `Setup.abi.json` | Setup ABI |
| `Wormhole.bytecode` | Proxy contract |
| `Wormhole.abi.json` | Proxy ABI |

## Deployment

Use the deployment script:

```bash
export PRIVATE_KEY="0x..."
./scripts/deploy/deploy-evm.sh <chain> <rpc_url> <guardian_addresses>
```

Example:
```bash
# Deploy to private Geth
./scripts/deploy/deploy-evm.sh geth http://localhost:8545 \
  "0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe"

# Deploy to Avalanche
./scripts/deploy/deploy-evm.sh avalanche ws://avalanche:8545/ws \
  "0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe"
```

## Manual Deployment

```bash
# 1. Deploy Implementation
IMPL=$(cast send --rpc-url $RPC --private-key $KEY --create \
  $(cat Implementation.bytecode) --json | jq -r '.contractAddress')

# 2. Deploy Setup
SETUP=$(cast send --rpc-url $RPC --private-key $KEY --create \
  $(cat Setup.bytecode) --json | jq -r '.contractAddress')

# 3. Create setup calldata
SETUP_DATA=$(cast calldata "setup(address,address[],uint16,uint16,bytes32,uint256)" \
  $IMPL '["0xguardian1"]' 2 2 \
  "0x0000000000000000000000000000000000000000000000000000000000000004" \
  31337)

# 4. Deploy Wormhole proxy
CONSTRUCTOR=$(cast abi-encode "constructor(address,bytes)" $SETUP $SETUP_DATA)
WORMHOLE=$(cast send --rpc-url $RPC --private-key $KEY --create \
  "$(cat Wormhole.bytecode)${CONSTRUCTOR:2}" --json | jq -r '.contractAddress')
```

## Building from Source

To rebuild contracts from the official Wormhole repository:

```bash
cd WormHole-Official-GitHub-Repo/ethereum

# Install dependencies
forge install

# Build
forge build --skip test

# Copy artifacts
cp out/Implementation.sol/Implementation.json ../Private-Guardian-Network/contracts/evm/artifacts/
```

