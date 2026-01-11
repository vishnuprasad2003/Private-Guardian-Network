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

#### Guardian Naming (CRITICAL!)

In **unsafeDevMode**, the guardian naming follows a **strict convention**:

| Hostname | Generated Signing Address |
|----------|--------------------------|
| `guardian-0` | `0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe` |
| `guardian-1` | `0x88D7D8B32a9105d228100E72dFFe2Fae0705D31c` |
| `guardian-2` | `0x58076F561CC62A47087B567C86f986426dFCD000` |
| `guardian-3` | `0x0000...` (continues) |

**Why is this important?**
- The guardian binary generates **deterministic** keys based on hostname
- If hostname is `guardian-0`, it ALWAYS generates the same key
- These addresses are **hardcoded in the Wormhole source code**
- You **CANNOT** change these mappings!

**Before starting a guardian in unsafeDevMode**:
```bash
sudo hostname guardian-0   # Set hostname
hostname                   # Verify it changed
bin/guardian start         # Start guardian (generates deterministic key)
```

**For production (non-dev mode)**:
- Generate your own keys: `bin/guardian keygen`
- Use any hostname you want
- Set `UNSAFE_DEV_MODE=false` in config

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
- **Solana**: Uses Wormhole Chain ID **1** (Solana)

---

## Solana Bridge Architecture

### Overview

The Solana Wormhole bridge is implemented as a **Solana program** (smart contract) that:
- Stores guardian sets
- Accepts posted VAAs
- Verifies VAA signatures
- Executes cross-chain actions based on VAA payloads

### Program Structure

```
Solana Wormhole Core Bridge Program
├── Bridge Account (PDA)
│   ├── Guardian Set Index
│   ├── Config (fee, expiry)
│   └── Last Lamports
│
├── Guardian Set Accounts (PDAs)
│   ├── Index
│   ├── Creation Time
│   └── Guardian Keys (array of 20-byte addresses)
│
├── Fee Collector Account (PDA)
│   └── Accumulated fees
│
└── Posted VAA Accounts (PDAs)
    ├── VAA Hash
    ├── Message Data
    └── Timestamp
```

### Program Derived Addresses (PDAs)

Solana uses PDAs (deterministic addresses) instead of regular accounts:

| Account | PDA Derivation | Purpose |
|---------|----------------|---------|
| Bridge | `[program_id, "Bridge"]` | Main bridge state |
| Guardian Set 0 | `[program_id, "GuardianSet", 0]` | Initial guardian set |
| Fee Collector | `[program_id, "FeeCollector"]` | Fee collection |
| Posted VAA | `[program_id, "PostedVAA", vaa_hash]` | Stored VAA |

### Initialization Process

When initializing the Solana bridge:

1. **Create Bridge Account**: Stores guardian set index and config
2. **Create Guardian Set Account**: Stores guardian addresses (20 bytes each)
3. **Create Fee Collector**: Account to receive message fees
4. **Set Initial Guardian Set**: Configure with your guardian addresses

**Initialization Parameters:**
- `guardianSetExpirationTime`: How long guardian set is valid (seconds)
- `fee`: Message fee in lamports (0 for free)
- `initialGuardians`: Array of guardian addresses (20 bytes each)

**Example:**
```javascript
const guardians = [
  Buffer.from('befa429d57cd18b7f8a4d91a2da9ab4af05d0fbe', 'hex') // guardian-0
];

// Initialize with:
// - Expiry: 86400 seconds (24 hours)
// - Fee: 0 lamports
// - Guardians: [guardian-0 address]
```

### Posting VAAs to Solana

When posting a VAA to Solana:

1. **Parse VAA**: Extract guardian set index, signatures, message data
2. **Verify Guardian Set**: Check if guardian set exists and is valid
3. **Verify Signatures**: Validate each signature against guardian keys
4. **Check Quorum**: Ensure enough signatures (quorum requirement)
5. **Create Posted VAA Account**: Store VAA as PDA
6. **Execute Action**: Process payload (if applicable)

**Posted VAA Account:**
- **Address**: Deterministic based on VAA hash
- **Owner**: Wormhole bridge program
- **Data**: Serialized VAA message
- **Lamports**: Rent-exempt amount

### Solana vs EVM Differences

| Aspect | EVM (Avalanche) | Solana |
|--------|-----------------|--------|
| Contract Type | Smart Contract | Program (BPF) |
| State Storage | Contract storage | Accounts (PDAs) |
| Guardian Set | Stored in contract | Separate account per set |
| VAA Verification | On-chain in contract | Program instruction |
| Posted VAAs | Event logs | Separate accounts |
| Fees | Gas (native token) | Lamports (SOL) |

### Guardian Observation on Solana

Guardians observe Solana by:
1. **Connecting to Solana RPC**: WebSocket or HTTP
2. **Watching Program Accounts**: Monitor Wormhole program PDAs
3. **Detecting Messages**: Observe `postMessage` instruction calls
4. **Signing VAAs**: Sign observed messages
5. **Storing VAAs**: Save signed VAAs for retrieval

**Solana Message Format:**
- Messages are posted via `postMessage` instruction
- Each message has: `emitter`, `sequence`, `payload`, `consistencyLevel`
- Guardians observe these and create VAAs

### Complete Solana Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User calls postMessage on Solana program                    │
│    - Emitter: Program-derived address                          │
│    - Sequence: Auto-incrementing                               │
│    - Payload: Arbitrary bytes                                  │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Guardian observes message                                    │
│    - Watches Solana program accounts                           │
│    - Detects new message                                        │
│    - Extracts: emitter, sequence, payload                       │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Guardian signs message                                        │
│    - Creates VAA with signature                                 │
│    - Broadcasts to other guardians                             │
│    - Collects signatures until quorum                          │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. VAA is posted to Solana bridge                               │
│    - postVAA instruction called                                 │
│    - Program verifies signatures                                │
│    - Creates Posted VAA account                                │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. Posted VAA can be used                                        │
│    - Other programs can read Posted VAA                        │
│    - Execute cross-chain actions                                │
│    - Complete transfers, etc.                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Solana Configuration

In `config/guardian.conf`:

```bash
# Solana RPC (HTTP for deployment, WebSocket for guardian)
SOLANA_RPC="http://127.0.0.1:8899"
SOLANA_WS="ws://127.0.0.1:8900"

# Wormhole Core Bridge program ID (after deployment)
SOLANA_CONTRACT="G9TA5QaG3XutR4LCCGzcfdoP6LB4e2YSp5D98vhN5cea"

# Deployer keypair path
SOLANA_KEYPAIR="~/.config/solana/id.json"
```

**Important Notes:**
- Guardian uses **WebSocket** (`SOLANA_WS`) for real-time observation
- Deployment scripts use **HTTP** (`SOLANA_RPC`) for transactions
- Program ID is generated once and reused
- Keypair must have SOL for transaction fees

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

## Configuration Architecture

### Single Source of Truth

All configuration is centralized in `config/guardian.conf`. This ensures:
- Change settings in ONE place, not multiple files
- Consistency across all scripts and services
- Easy deployment to multiple VMs (copy one file)

```
config/guardian.conf
        │
        ├──► bin/guardian      (bash - sources config)
        ├──► bin/anvil         (bash - sources config)
        ├──► bin/deploy        (bash - sources config)
        ├──► bin/api           (bash - sources config)
        │
        └──► src/lib/config.js (Node.js - parses config)
                    │
                    ├──► src/api/server.js
                    ├──► src/cli/fetch-vaa.js
                    └──► src/cli/post-vaa-solana.js
```

### Configuration Sections

| Section | Purpose | When to Change |
|---------|---------|----------------|
| Guardian Identity | `GUARDIAN_INDEX` | Different on each VM |
| Network Settings | `NUM_GUARDIANS` | When adding/removing guardians |
| Anvil/Geth | `ANVIL_PORT`, `GETH_CONTRACT` | After deployment |
| Avalanche | `AVALANCHE_RPC`, `AVALANCHE_CONTRACT` | Chain setup |
| Solana | `SOLANA_RPC`, `SOLANA_CONTRACT` | Chain setup |
| Ports | `P2P_PORT`, `GRPC_PORT` | Network planning |
| Guardian Addresses | `GUARDIAN_X_ADDRESS` | Reference only (deterministic) |

### Making Changes

1. **Edit ONLY** `config/guardian.conf`
2. **Restart** affected services:
   ```bash
   bin/guardian stop && bin/guardian start
   bin/api stop && bin/api start
   ```
3. Changes take effect immediately (no rebuild needed)

### Environment Variables

Some settings can be overridden via environment:

| Variable | Purpose | Priority |
|----------|---------|----------|
| `PRIVATE_KEY` | Deployer key (for security) | Env > Config |
| `CONFIG_FILE` | Custom config path | Env only |
| `GUARDIAND_BIN` | Custom guardiand path | Env only |

**Security Note**: Never put private keys in `guardian.conf`! Use environment variables for sensitive values.

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
| **Single Source of Truth** | All config in one file (`guardian.conf`) |

---

## Further Reading

- [Wormhole Documentation](https://docs.wormhole.com/)
- [Wormhole GitHub](https://github.com/wormhole-foundation/wormhole)
- [libp2p Documentation](https://docs.libp2p.io/)
- [Foundry (Anvil) Documentation](https://book.getfoundry.sh/)

