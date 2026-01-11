# Private Guardian Network Architecture

A comprehensive guide to understanding how the Wormhole private guardian network works.

## Table of Contents

1. [Overview](#overview)
2. [Core Concepts](#core-concepts)
3. [Architecture Components](#architecture-components)
4. [Message Flow](#message-flow)
5. [Guardian Consensus](#guardian-consensus)
6. [VAA Structure](#vaa-structure)
7. [Security Model](#security-model)
8. [Network Topology](#network-topology)

---

## Overview

### What is a Guardian Network?

A Guardian Network is a decentralized network of nodes (called "guardians") that observe blockchain events and collectively sign attestations called VAAs (Verifiable Action Approvals). These VAAs enable secure cross-chain communication.

### Why Private Guardian Network?

A **private** guardian network allows you to:
- Bridge assets between custom/private blockchains
- Control the trust assumptions (you choose the guardians)
- Operate independently from the public Wormhole network
- Test cross-chain applications before mainnet deployment

### This Implementation

This setup creates a private guardian network that bridges:
- **Avalanche L1 Subnet** (custom EVM chain)
- **Solana** (optional)
- **Private Ethereum (Anvil)** - Used as the guardian registry

---

## Core Concepts

### 1. Guardian

A **guardian** is a node that:
- Observes events on connected blockchains
- Signs messages it observes
- Participates in consensus with other guardians
- Stores and serves signed VAAs

Each guardian has:
- **Signing Key**: ECDSA key for signing VAAs
- **P2P Identity**: libp2p key for network communication
- **Node Name**: Identifier (e.g., `guardian-0`)

### 2. VAA (Verifiable Action Approval)

A **VAA** is a signed attestation that proves something happened on a source chain. It contains:
- The original message/event data
- Signatures from guardians
- Metadata (timestamp, sequence, etc.)

VAAs are the "proof" that enables cross-chain actions.

### 3. Emitter

An **emitter** is the entity that published a message. In EVM chains, this is the wallet address that called `publishMessage()` on the Wormhole contract.

### 4. Sequence

Each emitter has an auto-incrementing **sequence** number. Together with chain ID and emitter address, this creates a unique message identifier:
```
messageId = chainId/emitterAddress/sequence
Example: 6/000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d/5
```

### 5. Quorum

**Quorum** is the minimum number of guardian signatures required for a valid VAA:
```
quorum = floor(2/3 * totalGuardians) + 1
```

| Guardians | Quorum | Fault Tolerance |
|-----------|--------|-----------------|
| 1 | 1 | 0 |
| 3 | 3 | 0 |
| 5 | 4 | 1 |
| 7 | 5 | 2 |
| 13 | 9 | 4 |
| 19 | 13 | 6 |

### 6. Guardian Set

A **guardian set** is the list of authorized guardian public keys/addresses stored in the Wormhole contract. Guardians validate their signatures against this set.

---

## Architecture Components

### System Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         PRIVATE GUARDIAN NETWORK                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌──────────────┐      P2P (QUIC)       ┌──────────────┐               │
│   │  Guardian-0  │◄────────────────────►│  Guardian-1  │               │
│   │  (Bootstrap) │                       │              │               │
│   └──────┬───────┘                       └──────┬───────┘               │
│          │                                      │                        │
│          │         ┌──────────────┐            │                        │
│          └────────►│  Guardian-2  │◄───────────┘                        │
│                    └──────┬───────┘                                     │
│                           │                                              │
├───────────────────────────┼──────────────────────────────────────────────┤
│                           │                                              │
│   BLOCKCHAIN CONNECTIONS  │                                              │
│                           ▼                                              │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                                                                  │   │
│   │  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐           │   │
│   │  │   Anvil     │   │ Avalanche   │   │   Solana    │           │   │
│   │  │  (Registry) │   │  L1 Subnet  │   │  (Optional) │           │   │
│   │  │             │   │             │   │             │           │   │
│   │  │ Chain ID: 2 │   │ Chain ID: 6 │   │ Chain ID: 1 │           │   │
│   │  │             │   │             │   │             │           │   │
│   │  │  Wormhole   │   │  Wormhole   │   │  Wormhole   │           │   │
│   │  │  Contract   │   │  Contract   │   │  Program    │           │   │
│   │  └─────────────┘   └─────────────┘   └─────────────┘           │   │
│   │                                                                  │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Details

#### 1. Anvil (Guardian Registry)

**Purpose**: Stores the authoritative guardian set.

Anvil is a local Ethereum node that:
- Hosts the Wormhole contract with the guardian set
- Acts as the "source of truth" for who the guardians are
- All guardians connect to this same Anvil instance
- Provides `ethRPC` endpoint for guardians

**Why Anvil instead of Geth?**
- Auto-mines blocks (no consensus client needed)
- Simpler setup for private networks
- Persistent state support
- Pre-funded accounts for easy deployment

#### 2. Guardian Node (guardiand)

**Purpose**: Observes chains, signs VAAs, participates in consensus.

The guardian node:
- Connects to all configured chains via WebSocket RPC
- Watches for `LogMessagePublished` events
- Signs observed messages with its private key
- Broadcasts signatures to other guardians via P2P
- Aggregates signatures and stores complete VAAs
- Serves VAAs via gRPC API

**Key Flags**:
- `--unsafeDevMode`: Bypasses chain ID verification (required for custom chains)
- `--ethRPC`: Ethereum/Anvil WebSocket URL (guardian registry)
- `--avalancheRPC`: Avalanche WebSocket URL
- `--bootstrap`: P2P bootstrap peer address

#### 3. API Server

**Purpose**: REST API for fetching VAAs (like Wormholescan).

The API server:
- Provides HTTP endpoints for VAA retrieval
- Communicates with guardian via admin socket
- Returns VAAs in hex format
- Provides health checks and metrics

#### 4. Wormhole Contracts

**On EVM Chains (Avalanche, Anvil)**:
- `Implementation.sol`: Core logic
- `Setup.sol`: Initialization
- `Wormhole.sol`: Proxy contract

**Key Functions**:
- `publishMessage(nonce, payload, consistencyLevel)`: Emit a message
- `parseAndVerifyVM(vaa)`: Verify a VAA
- `getCurrentGuardianSetIndex()`: Get active guardian set
- `getGuardianSet(index)`: Get guardian addresses

---

## Message Flow

### Publishing a Message (Source Chain)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. USER PUBLISHES MESSAGE                                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   User Wallet                                                            │
│       │                                                                  │
│       │ cast send $CONTRACT "publishMessage(uint32,bytes,uint8)"        │
│       │           nonce    payload   consistencyLevel                   │
│       ▼                                                                  │
│   ┌─────────────────────────────────┐                                   │
│   │     Wormhole Contract           │                                   │
│   │     (Avalanche L1)              │                                   │
│   │                                 │                                   │
│   │  1. Increment sequence          │                                   │
│   │  2. Emit LogMessagePublished    │                                   │
│   │     - sender (emitter)          │                                   │
│   │     - sequence                  │                                   │
│   │     - nonce                     │                                   │
│   │     - payload                   │                                   │
│   │     - consistencyLevel          │                                   │
│   └─────────────────────────────────┘                                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Guardian Observation and Signing

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 2. GUARDIANS OBSERVE AND SIGN                                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   LogMessagePublished Event                                              │
│       │                                                                  │
│       │  (WebSocket subscription)                                        │
│       ▼                                                                  │
│   ┌─────────────────────────────────┐                                   │
│   │     Guardian Node               │                                   │
│   │                                 │                                   │
│   │  1. Receive event               │                                   │
│   │  2. Wait for finality           │                                   │
│   │  3. Create observation:         │                                   │
│   │     - chainId                   │                                   │
│   │     - emitterAddress            │                                   │
│   │     - sequence                  │                                   │
│   │     - timestamp                 │                                   │
│   │     - payload                   │                                   │
│   │  4. Hash observation            │                                   │
│   │  5. Sign hash with guardian key │                                   │
│   │  6. Broadcast signature to P2P  │                                   │
│   └─────────────────────────────────┘                                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Consensus and VAA Creation

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 3. CONSENSUS AND VAA CREATION                                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                     │
│   │ Guardian-0  │  │ Guardian-1  │  │ Guardian-2  │                     │
│   │ Signature   │  │ Signature   │  │ Signature   │                     │
│   └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                     │
│          │                │                │                             │
│          └────────────────┼────────────────┘                             │
│                           │                                              │
│                           ▼                                              │
│                  ┌─────────────────┐                                    │
│                  │ Collect sigs    │                                    │
│                  │ until quorum    │                                    │
│                  └────────┬────────┘                                    │
│                           │                                              │
│                           ▼                                              │
│                  ┌─────────────────┐                                    │
│                  │   Create VAA    │                                    │
│                  │                 │                                    │
│                  │ - version       │                                    │
│                  │ - guardianSet   │                                    │
│                  │ - signatures[]  │                                    │
│                  │ - timestamp     │                                    │
│                  │ - nonce         │                                    │
│                  │ - emitterChain  │                                    │
│                  │ - emitter       │                                    │
│                  │ - sequence      │                                    │
│                  │ - consistency   │                                    │
│                  │ - payload       │                                    │
│                  └────────┬────────┘                                    │
│                           │                                              │
│                           ▼                                              │
│                  ┌─────────────────┐                                    │
│                  │  Store in DB    │                                    │
│                  │  Serve via API  │                                    │
│                  └─────────────────┘                                    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### VAA Verification (Target Chain)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 4. VAA VERIFICATION ON TARGET CHAIN                                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Application fetches VAA from API                                       │
│       │                                                                  │
│       │  curl /api/v1/vaas/6/emitter/sequence                           │
│       ▼                                                                  │
│   ┌─────────────────────────────────┐                                   │
│   │         VAA (hex)               │                                   │
│   └──────────────┬──────────────────┘                                   │
│                  │                                                       │
│                  │  Submit to target chain                               │
│                  ▼                                                       │
│   ┌─────────────────────────────────┐                                   │
│   │   Target Chain Contract         │                                   │
│   │   (e.g., Solana Wormhole)       │                                   │
│   │                                 │                                   │
│   │  1. Parse VAA                   │                                   │
│   │  2. Verify guardian set index   │                                   │
│   │  3. Verify each signature       │                                   │
│   │  4. Check quorum reached        │                                   │
│   │  5. Execute payload action      │                                   │
│   └─────────────────────────────────┘                                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Guardian Consensus

### How Consensus Works

1. **Observation**: Each guardian independently observes blockchain events
2. **Signing**: Each guardian signs what it observed
3. **Broadcasting**: Signatures are shared via P2P gossip
4. **Aggregation**: Guardians collect signatures from peers
5. **Quorum**: Once enough signatures are collected, VAA is complete

### P2P Network

Guardians communicate via **libp2p** using:
- **Protocol**: QUIC (UDP-based, encrypted)
- **Port**: 8999 (default)
- **Discovery**: Bootstrap peer (guardian-0)

**Multiaddr Format**:
```
/ip4/<IP>/udp/<PORT>/quic-v1/p2p/<PEER_ID>
```

Example:
```
/ip4/10.0.0.10/udp/8999/quic-v1/p2p/12D3KooWxxxxxxxxx
```

### Consistency Levels

When publishing a message, you specify a consistency level:
- `1` (Confirmed): Message is confirmed after 1 block
- `201` (Finalized): Wait for chain finality (varies by chain)

For private networks, `1` is typically sufficient.

---

## VAA Structure

### Binary Format

```
┌────────────────────────────────────────────────────────────────────────┐
│ Byte  │ Field                │ Description                             │
├───────┼──────────────────────┼─────────────────────────────────────────┤
│ 0     │ Version              │ VAA version (currently 1)               │
│ 1-4   │ GuardianSetIndex     │ Which guardian set signed this          │
│ 5     │ SignatureCount       │ Number of signatures                    │
│ 6+    │ Signatures[]         │ Array of (index, r, s, v) = 66 bytes ea │
│       │                      │                                         │
│ After signatures:            │                                         │
│ +0-3  │ Timestamp            │ Unix timestamp                          │
│ +4-7  │ Nonce                │ User-provided nonce                     │
│ +8-9  │ EmitterChain         │ Wormhole chain ID                       │
│ +10-41│ EmitterAddress       │ 32-byte emitter address                 │
│ +42-49│ Sequence             │ Message sequence number                 │
│ +50   │ ConsistencyLevel     │ Finality level                          │
│ +51+  │ Payload              │ Arbitrary bytes                         │
└────────────────────────────────────────────────────────────────────────┘
```

### Example VAA (Decoded)

```json
{
  "version": 1,
  "guardianSetIndex": 0,
  "signatures": [
    {
      "index": 0,
      "signature": "e36790fd04e3cee2b399495fa10273e6a9a360e3..."
    }
  ],
  "timestamp": "2026-01-11T11:08:56+05:30",
  "nonce": 1,
  "emitterChain": 6,
  "emitterAddress": "000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d",
  "sequence": 0,
  "consistencyLevel": 1,
  "payload": "48656c6c6f"  // "Hello" in hex
}
```

---

## Security Model

### Trust Assumptions

1. **Guardian Trust**: You trust at least 2/3 + 1 of guardians to be honest
2. **Chain Security**: Source and target chains are secure
3. **Key Security**: Guardian private keys are not compromised

### Attack Vectors

| Attack | Mitigation |
|--------|------------|
| Fake VAA | Requires 2/3+1 guardian signatures |
| Replay | Sequence numbers prevent replay |
| Key Compromise | Replace guardian set via governance |
| Eclipse Attack | Multiple P2P connections |
| Chain Reorg | Wait for finality (consistency level) |

### Best Practices

1. **Key Management**:
   - Store guardian keys securely (HSM in production)
   - Never expose private keys
   - Use unique keys per guardian

2. **Network Security**:
   - Firewall guardian nodes
   - Use private network for P2P
   - Monitor for unusual activity

3. **Redundancy**:
   - Run multiple guardians (3+)
   - Geographic distribution
   - Multiple RPC endpoints

---

## Network Topology

### Single Node (Testing)

```
┌────────────────────────────────────────┐
│           Single VM                    │
│                                        │
│  ┌──────────┐  ┌──────────┐           │
│  │  Anvil   │  │ Guardian │           │
│  │  :8545   │  │   :7000  │           │
│  └──────────┘  └──────────┘           │
│                     │                  │
│               ┌─────┴─────┐           │
│               │    API    │           │
│               │   :3000   │           │
│               └───────────┘           │
└────────────────────────────────────────┘
```

### Multi-Node (Production)

```
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│     VM-0        │   │     VM-1        │   │     VM-2        │
│   (Bootstrap)   │   │                 │   │                 │
│                 │   │                 │   │                 │
│ ┌─────────────┐ │   │ ┌─────────────┐ │   │ ┌─────────────┐ │
│ │   Anvil     │◄├───┼─┤ Guardian-1  │◄├───┼─┤ Guardian-2  │ │
│ │   :8545     │ │   │ │   :7000     │ │   │ │   :7000     │ │
│ └─────────────┘ │   │ └─────────────┘ │   │ └─────────────┘ │
│                 │   │        ▲        │   │        ▲        │
│ ┌─────────────┐ │   │        │        │   │        │        │
│ │ Guardian-0  │◄├───┼────────┴────────┼───┼────────┘        │
│ │ (Bootstrap) │ │   │                 │   │                 │
│ │   :7000     │ │   │                 │   │                 │
│ └─────────────┘ │   │                 │   │                 │
│                 │   │                 │   │                 │
│ ┌─────────────┐ │   │                 │   │                 │
│ │    API      │ │   │                 │   │                 │
│ │   :3000     │ │   │                 │   │                 │
│ └─────────────┘ │   │                 │   │                 │
└─────────────────┘   └─────────────────┘   └─────────────────┘

         │                    │                    │
         └────────────────────┼────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │   P2P Network     │
                    │  (libp2p/QUIC)    │
                    │    UDP :8999      │
                    └───────────────────┘
```

### Port Reference

| Port | Protocol | Service | Access |
|------|----------|---------|--------|
| 8545 | TCP | Anvil RPC | Internal |
| 8999 | UDP | Guardian P2P | Between guardians |
| 7000 | TCP | Guardian gRPC | Internal |
| 6600 | TCP | Guardian Metrics | Monitoring |
| 3000 | TCP | API Server | External |

---

## Chain IDs

### Wormhole Chain IDs

| Chain | ID | Description |
|-------|----|-------------|
| Solana | 1 | Solana mainnet/devnet |
| Ethereum | 2 | Ethereum mainnet |
| Avalanche | 6 | Avalanche C-Chain |
| BSC | 4 | BNB Smart Chain |
| Polygon | 5 | Polygon PoS |

For this private network:
- **Anvil (Registry)**: Uses Wormhole Chain ID **2** (Ethereum)
- **Avalanche L1**: Uses Wormhole Chain ID **6** (Avalanche)

---

## Files and Data Storage

### Key Files

| File | Purpose | Security |
|------|---------|----------|
| `keys/guardian-X.key` | Guardian signing key | **CRITICAL** - Backup securely |
| `keys/node-X.key` | P2P identity key | Important - Backup |
| `config/guardian.conf` | Configuration | Contains sensitive URLs |

### Data Directories

| Directory | Contents | Can Rebuild? |
|-----------|----------|--------------|
| `data/guardian-X/` | BadgerDB (VAA store) | Yes (re-observe) |
| `data/anvil-state.json` | Anvil blockchain | No - Contains contracts |
| `logs/` | Log files | Yes |

### Backup Priority

1. **Critical**: Guardian keys, Anvil state
2. **Important**: Configuration, Node keys
3. **Optional**: Logs, Guardian data (can rebuild)

---

## Glossary

| Term | Definition |
|------|------------|
| **VAA** | Verifiable Action Approval - Signed cross-chain message |
| **Guardian** | Node that observes and signs messages |
| **Emitter** | Entity that published a message (wallet address) |
| **Sequence** | Auto-incrementing message counter per emitter |
| **Quorum** | Minimum signatures required (2/3 + 1) |
| **Guardian Set** | List of authorized guardian addresses |
| **Consistency Level** | Finality requirement for messages |
| **Bootstrap Peer** | First guardian that others connect to |
| **P2P** | Peer-to-peer network between guardians |
| **gRPC** | Protocol for VAA retrieval |

---

## Further Reading

- [Wormhole Documentation](https://docs.wormhole.com/)
- [Wormhole GitHub](https://github.com/wormhole-foundation/wormhole)
- [libp2p Documentation](https://docs.libp2p.io/)
- [Foundry (Anvil) Documentation](https://book.getfoundry.sh/)

