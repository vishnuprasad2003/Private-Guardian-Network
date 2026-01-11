# Solana Contracts

Pre-compiled Wormhole programs for Solana.

## Files

| File | Description |
|------|-------------|
| `bridge.so` | Core bridge program (BPF bytecode) |
| `wormhole.json` | Program IDL |
| `program-id.json` | Deployed program keypair |
| `checksums.txt` | File checksums |

## Deployment

```bash
# 1. Generate program ID (first run)
node src/cli/deploy-solana.js

# 2. Deploy program
solana program deploy \
  --program-id contracts/solana/artifacts/program-id.json \
  contracts/solana/artifacts/bridge.so \
  --url http://localhost:8899

# 3. Initialize (second run)
export GUARDIAN_SET='["befa429d57cd18b7f8a4d91a2da9ab4af05d0fbe"]'
node src/cli/deploy-solana.js
```

## Building from Source

```bash
cd WormHole-Official-GitHub-Repo/solana

# Install Solana tools
sh -c "$(curl -sSfL https://release.solana.com/stable/install)"

# Build
cargo build-sbf

# Copy artifacts
cp target/deploy/bridge.so ../Private-Guardian-Network/contracts/solana/artifacts/
```

## Program Initialization Parameters

| Parameter | Description |
|-----------|-------------|
| `guardians` | Array of guardian public keys |
| `fee` | Message fee in lamports |
| `expiration_time` | Guardian set expiration |

## Posting VAAs

After deployment, VAAs can be posted using:

```bash
node src/cli/post-vaa-solana.js <chainId> <emitter> <sequence>
```
