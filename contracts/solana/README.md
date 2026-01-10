# Solana Wormhole Bridge Contracts

## Pre-built Artifacts

The `artifacts/` directory contains pre-built Solana programs from the official Wormhole repository:

| File | Description | Size |
|------|-------------|------|
| `bridge.so` | Core Wormhole Bridge (required) | ~317 KB |
| `token_bridge.so` | Token Bridge (optional) | ~516 KB |
| `wormhole.json` | IDL for client interaction | ~18 KB |

## Building from Source

### Prerequisites

1. **Docker** (required for reproducible builds)
2. **Rust** (nightly-2022-02-24)
3. **Solana CLI** (for deployment)

### Build Steps

```bash
# Navigate to Wormhole repo
cd "/home/vishnu-intain/Documents/Block Chain/Cross Chain/WormHole-Official-GitHub-Repo/solana"

# Build using Docker (recommended for reproducibility)
make artifacts SVM=solana NETWORK=devnet

# Output will be in: artifacts-solana-devnet/
```

### Manual Build (without Docker)

```bash
# Install specific Rust version
rustup install nightly-2022-02-24
rustup default nightly-2022-02-24

# Install Solana BPF tools
cargo install --git https://github.com/solana-labs/cargo-build-bpf

# Set environment variables
export BRIDGE_ADDRESS=Bridge1p5gheXUvJ6jGWGeCsgPKgnE3YgdGKRVCMY9o
export CHAIN_ID=1

# Build
cd bridge/program
cargo build-bpf

# Output: target/deploy/wormhole_bridge_solana.so
```

## Deployment

### 1. Deploy Program to Solana

```bash
# Set Solana config
solana config set --url http://127.0.0.1:8899  # Local validator
# OR
solana config set --url https://api.devnet.solana.com  # Devnet

# Deploy the program
solana program deploy artifacts/bridge.so --keypair /path/to/deployer.json

# Note the program ID output!
```

### 2. Initialize the Bridge

```bash
cd "/home/vishnu-intain/Documents/Block Chain/Cross Chain/WormHole-Official-GitHub-Repo/solana/scripts"

# Install dependencies
npm install

# Initialize with YOUR guardian
npx ts-node initialize-core.ts \
    --rpc http://127.0.0.1:8899 \
    --bridge <PROGRAM_ID> \
    --payer /path/to/payer.json \
    --guardians "beFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe"
```

## Guardian Address

For your private network, use the devnet guardian address:

```
0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe
```

This MUST match the guardian set on:
- Private Geth (guardian registry)
- Avalanche L1 contract

## Verification

After deployment, verify the guardian set:

```bash
# Using Solana CLI
solana account <GUARDIAN_SET_PDA> --output json

# Or check via your application
```

## File Checksums

```
84277ddcc1c5c6c7813d6ed0fd1631453527d2fc0587ed111cdf1ae623705694  bridge.so
9fce1ebeb4e7df75d5f3e5bfee4a3bae32b50b117d44f1a7caaa9aabb95cd25a  token_bridge.so
```

Verify with:
```bash
cd artifacts
sha256sum -c checksums.txt
```
