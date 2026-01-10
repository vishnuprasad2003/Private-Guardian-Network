#!/usr/bin/env node
/**
 * Deploy and Initialize Solana Wormhole Core Bridge Program
 * 
 * Usage:
 *   node scripts/deploy-solana-core.js
 * 
 * Environment Variables:
 *   SOLANA_RPC - Solana RPC URL (default: http://127.0.0.1:8899)
 *   SOLANA_KEYPAIR - Path to keypair file or base58 private key
 *   GUARDIAN_SET - JSON array of guardian addresses (hex, no 0x prefix)
 *   FEE - Bridge fee in lamports (default: 100000)
 *   EXPIRATION_TIME - Guardian set expiration in seconds (default: 86400)
 */

const { Connection, Keypair, PublicKey } = require('@solana/web3.js');
const { createInitializeInstruction } = require('@certusone/wormhole-sdk/lib/cjs/solana/wormhole');
const { AnchorProvider, Wallet } = require('@coral-xyz/anchor');
const fs = require('fs');
const path = require('path');
const bs58 = require('bs58');

const rootDir = path.resolve(__dirname, '..');

// Load configuration
const SOLANA_RPC = process.env.SOLANA_RPC || 'http://127.0.0.1:8899';
const SOLANA_KEYPAIR = process.env.SOLANA_KEYPAIR || path.join(rootDir, 'keys', 'solana-deployer.json');
const GUARDIAN_SET_STR = process.env.GUARDIAN_SET;
const FEE = BigInt(process.env.FEE || '100000');
const EXPIRATION_TIME = parseInt(process.env.EXPIRATION_TIME || '86400');

// Program ID (will be generated or use existing)
const PROGRAM_SO = path.join(rootDir, 'contracts', 'solana', 'artifacts', 'bridge.so');
const PROGRAM_ID_FILE = path.join(rootDir, 'contracts', 'solana', 'artifacts', 'program-id.json');

async function main() {
    console.log('='.repeat(70));
    console.log('Solana Wormhole Core Bridge Deployment');
    console.log('='.repeat(70));
    console.log(`RPC: ${SOLANA_RPC}`);
    console.log(`Keypair: ${SOLANA_KEYPAIR}`);
    console.log('');

    // Load or generate keypair
    let payer;
    if (fs.existsSync(SOLANA_KEYPAIR)) {
        const keypairData = JSON.parse(fs.readFileSync(SOLANA_KEYPAIR, 'utf-8'));
        payer = Keypair.fromSecretKey(Uint8Array.from(keypairData));
        console.log(`Loaded keypair: ${payer.publicKey.toString()}`);
    } else {
        // Try as base58 string
        try {
            payer = Keypair.fromSecretKey(bs58.decode(SOLANA_KEYPAIR));
            console.log(`Loaded keypair from base58: ${payer.publicKey.toString()}`);
        } catch (e) {
            console.error(`Error: Keypair file not found: ${SOLANA_KEYPAIR}`);
            console.error('Generate a keypair with: solana-keygen new -o keys/solana-deployer.json');
            process.exit(1);
        }
    }

    // Check program binary
    if (!fs.existsSync(PROGRAM_SO)) {
        console.error(`Error: Program binary not found: ${PROGRAM_SO}`);
        console.error('Build it first: cd WormHole-Official-GitHub-Repo/solana && cargo build-sbf');
        process.exit(1);
    }

    // Load or generate program ID
    let programId;
    let programKeypair;
    
    if (fs.existsSync(PROGRAM_ID_FILE)) {
        // Try to load as Solana keypair format (JSON array)
        try {
            const keypairData = JSON.parse(fs.readFileSync(PROGRAM_ID_FILE, 'utf-8'));
            if (Array.isArray(keypairData)) {
                // Standard Solana keypair format
                programKeypair = Keypair.fromSecretKey(Uint8Array.from(keypairData));
                programId = programKeypair.publicKey;
                console.log(`Using existing program ID: ${programId.toString()}`);
            } else if (keypairData.programId) {
                // Our custom format - convert to keypair
                programId = new PublicKey(keypairData.programId);
                if (keypairData.keypair && Array.isArray(keypairData.keypair)) {
                    programKeypair = Keypair.fromSecretKey(Uint8Array.from(keypairData.keypair));
                    console.log(`Using existing program ID: ${programId.toString()}`);
                } else {
                    throw new Error('Keypair data missing in program-id.json');
                }
            } else {
                throw new Error('Invalid program-id.json format');
            }
        } catch (e) {
            console.error(`Error reading program-id.json: ${e.message}`);
            console.error('Regenerating program ID...');
            // Fall through to generate new one
        }
    }
    
    if (!programId) {
        // Generate new program ID
        programKeypair = Keypair.generate();
        programId = programKeypair.publicKey;
        
        // Save as Solana keypair format (JSON array)
        fs.writeFileSync(PROGRAM_ID_FILE, JSON.stringify(Array.from(programKeypair.secretKey)));
        
        console.log(`Generated new program ID: ${programId.toString()}`);
        console.log(`⚠️  You need to deploy the program with this ID first!`);
        console.log('');
        console.log('Run this command:');
        console.log(`  solana program deploy --program-id "${PROGRAM_ID_FILE}" "${PROGRAM_SO}"`);
        console.log('');
        console.log('Or with full paths:');
        const fullProgramId = path.resolve(PROGRAM_ID_FILE);
        const fullProgramSo = path.resolve(PROGRAM_SO);
        console.log(`  solana program deploy --program-id "${fullProgramId}" "${fullProgramSo}"`);
        console.log('');
        console.log('After deployment, run this script again to initialize.');
        process.exit(0);
    }

    // Parse guardian set
    if (!GUARDIAN_SET_STR) {
        // Try to load from config
        const configPath = path.join(rootDir, 'config', 'guardian.conf');
        if (fs.existsSync(configPath)) {
            const config = fs.readFileSync(configPath, 'utf-8');
            const guardians = [];
            
            for (const line of config.split('\n')) {
                const match = line.match(/^GUARDIAN_(\d+)_ADDRESS="(0x[a-fA-F0-9]+)"/i);
                if (match) {
                    guardians.push(match[2].replace(/^0x/i, ''));
                }
            }
            
            if (guardians.length > 0) {
                console.log(`Loaded ${guardians.length} guardians from config`);
                var guardianSet = guardians;
            } else {
                console.error('Error: GUARDIAN_SET not provided and not found in config');
                process.exit(1);
            }
        } else {
            console.error('Error: GUARDIAN_SET environment variable required');
            console.error('Format: GUARDIAN_SET=\'["befa429d57cd18b7f8a4d91a2da9ab4af05d0fbe",...]\'');
            process.exit(1);
        }
    } else {
        guardianSet = JSON.parse(GUARDIAN_SET_STR);
    }

    if (!Array.isArray(guardianSet) || guardianSet.length === 0) {
        console.error('Error: GUARDIAN_SET must be a non-empty JSON array');
        process.exit(1);
    }

    // Convert guardian addresses to buffers (20 bytes each)
    const guardianSetBuffer = guardianSet.map((guardian) => {
        const addr = guardian.replace(/^0x/i, '');
        if (addr.length !== 40) {
            throw new Error(`Invalid guardian address length: ${guardian}`);
        }
        return Buffer.from(addr, 'hex');
    });

    console.log(`Guardian Set: ${guardianSet.length} guardians`);
    console.log(`Fee: ${FEE} lamports`);
    console.log(`Expiration Time: ${EXPIRATION_TIME} seconds`);
    console.log('');

    // Connect to Solana
    const connection = new Connection(SOLANA_RPC, 'confirmed');
    
    // Check balance
    const balance = await connection.getBalance(payer.publicKey);
    console.log(`Payer balance: ${balance / 1e9} SOL`);
    if (balance < 1e9) {
        console.error('Error: Insufficient balance. Need at least 1 SOL for deployment.');
        console.error(`Airdrop with: solana airdrop 2 ${payer.publicKey.toString()}`);
        process.exit(1);
    }

    // Check if program is deployed
    const programInfo = await connection.getAccountInfo(programId);
    if (!programInfo || !programInfo.executable) {
        console.error(`Error: Program ${programId.toString()} is not deployed`);
        console.error(`Deploy with: solana program deploy --program-id ${PROGRAM_ID_FILE} ${PROGRAM_SO}`);
        process.exit(1);
    }

    console.log('Program is deployed ✓');
    console.log('');

    // Create provider
    const provider = new AnchorProvider(connection, new Wallet(payer), {
        commitment: 'confirmed'
    });

    // Create initialize instruction
    console.log('Creating initialize instruction...');
    const initializeIx = createInitializeInstruction(
        programId,
        payer.publicKey.toString(),
        EXPIRATION_TIME,
        FEE,
        guardianSetBuffer
    );

    // Send transaction
    console.log('Sending initialize transaction...');
    const transaction = new (require('@solana/web3.js').Transaction)();
    transaction.add(initializeIx);

    const signature = await provider.sendAndConfirm(transaction);
    
    console.log('');
    console.log('='.repeat(70));
    console.log('✅ Solana Core Bridge Initialized Successfully!');
    console.log('='.repeat(70));
    console.log(`Program ID: ${programId.toString()}`);
    console.log(`Transaction: ${signature}`);
    console.log(`RPC: ${SOLANA_RPC}`);
    console.log('');
    console.log('Add to guardian.conf:');
    console.log(`  SOLANA_CONTRACT="${programId.toString()}"`);
    console.log('='.repeat(70));
}

main().catch((error) => {
    console.error('Error:', error);
    process.exit(1);
});

