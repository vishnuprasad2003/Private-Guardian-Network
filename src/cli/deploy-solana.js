#!/usr/bin/env node
/**
 * Deploy and Initialize Solana Wormhole Core Bridge
 * 
 * ALL SETTINGS ARE READ FROM config/guardian.conf
 * 
 * Usage:
 *   node src/cli/deploy-solana.js [command]
 * 
 * Commands:
 *   generate   - Generate program ID (first step)
 *   deploy     - Deploy program to Solana (manual step - shows command)
 *   initialize - Initialize with guardian set
 *   status     - Check deployment status
 * 
 * Configuration (from guardian.conf):
 *   SOLANA_RPC       - Solana RPC URL
 *   SOLANA_KEYPAIR   - Path to deployer keypair  
 *   GUARDIAN_ADDRESSES - Guardian addresses for initialization
 */

const { Connection, Keypair, PublicKey, Transaction, SystemProgram, sendAndConfirmTransaction } = require('@solana/web3.js');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const config = require('../lib/config');

const ROOT_DIR = config.ROOT_DIR;
const cfg = config.loadConfig();
const solanaConfig = config.getSolanaConfig();

// Configuration from guardian.conf
const SOLANA_RPC = solanaConfig.rpc;
const KEYPAIR_PATH = solanaConfig.keypair.replace('~', process.env.HOME);
const ARTIFACTS_DIR = path.join(ROOT_DIR, 'contracts', 'solana', 'artifacts');
const PROGRAM_ID_FILE = path.join(ARTIFACTS_DIR, 'program-id.json');

// Guardian set from config
function getGuardianSet() {
    if (process.env.GUARDIAN_SET) {
        try {
            return JSON.parse(process.env.GUARDIAN_SET);
        } catch (e) {
            // Might be comma-separated
        }
    }
    
    const addresses = cfg.GUARDIAN_ADDRESSES || cfg.GUARDIAN_0_ADDRESS;
    return addresses.split(',').map(a => a.trim().replace(/^0x/i, '').toLowerCase());
}

function getNumGuardians() {
    return parseInt(cfg.NUM_GUARDIANS || '1', 10);
}

async function showStatus() {
    console.log('='.repeat(60));
    console.log('Solana Wormhole Core Bridge - Status');
    console.log('='.repeat(60));
    console.log('');
    console.log('Configuration (from config/guardian.conf):');
    console.log(`  SOLANA_RPC:      ${SOLANA_RPC}`);
    console.log(`  SOLANA_KEYPAIR:  ${KEYPAIR_PATH}`);
    console.log(`  SOLANA_CONTRACT: ${cfg.SOLANA_CONTRACT || 'not set'}`);
    console.log(`  NUM_GUARDIANS:   ${getNumGuardians()}`);
    console.log('');
    
    // Check connection
    try {
        const connection = new Connection(SOLANA_RPC, 'confirmed');
        const version = await connection.getVersion();
        console.log(`✅ Solana RPC connected (version: ${version['solana-core']})`);
    } catch (e) {
        console.log(`❌ Solana RPC not reachable: ${e.message}`);
        return;
    }
    
    // Check keypair
    if (fs.existsSync(KEYPAIR_PATH)) {
        const keypairData = JSON.parse(fs.readFileSync(KEYPAIR_PATH, 'utf-8'));
        const payer = Keypair.fromSecretKey(Uint8Array.from(keypairData));
        const connection = new Connection(SOLANA_RPC, 'confirmed');
        const balance = await connection.getBalance(payer.publicKey);
        console.log(`✅ Keypair loaded: ${payer.publicKey}`);
        console.log(`   Balance: ${balance / 1e9} SOL`);
    } else {
        console.log(`❌ Keypair not found: ${KEYPAIR_PATH}`);
    }
    
    // Check program ID
    if (fs.existsSync(PROGRAM_ID_FILE)) {
        const programData = JSON.parse(fs.readFileSync(PROGRAM_ID_FILE, 'utf-8'));
        const programKeypair = Keypair.fromSecretKey(Uint8Array.from(programData));
        console.log(`✅ Program ID generated: ${programKeypair.publicKey}`);
        
        // Check if deployed
        const connection = new Connection(SOLANA_RPC, 'confirmed');
        const programInfo = await connection.getAccountInfo(programKeypair.publicKey);
        if (programInfo) {
            console.log(`✅ Program deployed (${programInfo.data.length} bytes)`);
        } else {
            console.log(`❌ Program not deployed yet`);
        }
    } else {
        console.log(`❌ Program ID not generated yet`);
        console.log(`   Run: node src/cli/deploy-solana.js generate`);
    }
    
    // Guardian info
    const guardians = getGuardianSet();
    console.log('');
    console.log(`Guardians (${guardians.length}):`);
    guardians.forEach((g, i) => console.log(`  ${i}: 0x${g}`));
}

async function generateProgramId() {
    console.log('='.repeat(60));
    console.log('Generating Solana Program ID');
    console.log('='.repeat(60));
    console.log('');
    
    // Create artifacts directory
    if (!fs.existsSync(ARTIFACTS_DIR)) {
        fs.mkdirSync(ARTIFACTS_DIR, { recursive: true });
    }
    
    if (fs.existsSync(PROGRAM_ID_FILE)) {
        const programData = JSON.parse(fs.readFileSync(PROGRAM_ID_FILE, 'utf-8'));
        const programKeypair = Keypair.fromSecretKey(Uint8Array.from(programData));
        console.log(`Program ID already exists: ${programKeypair.publicKey}`);
        console.log('');
        console.log('To regenerate, delete:');
        console.log(`  rm ${PROGRAM_ID_FILE}`);
        return;
    }
    
    const programKeypair = Keypair.generate();
    
    // Save as Solana keypair format (array)
    fs.writeFileSync(
        PROGRAM_ID_FILE,
        JSON.stringify(Array.from(programKeypair.secretKey))
    );
    
    console.log(`✅ Program ID generated: ${programKeypair.publicKey}`);
    console.log(`   Saved to: ${PROGRAM_ID_FILE}`);
    console.log('');
    console.log('Next steps:');
    console.log('1. Build bridge.so (see contracts/solana/README.md)');
    console.log('2. Deploy with:');
    console.log(`   solana program deploy \\`);
    console.log(`     --program-id ${PROGRAM_ID_FILE} \\`);
    console.log(`     ${path.join(ARTIFACTS_DIR, 'bridge.so')} \\`);
    console.log(`     --url ${SOLANA_RPC}`);
    console.log('');
    console.log('3. Then initialize:');
    console.log(`   node src/cli/deploy-solana.js initialize`);
}

async function showDeployCommand() {
    console.log('='.repeat(60));
    console.log('Deploy Solana Program');
    console.log('='.repeat(60));
    console.log('');
    
    if (!fs.existsSync(PROGRAM_ID_FILE)) {
        console.log('❌ Program ID not generated yet');
        console.log('   Run: node src/cli/deploy-solana.js generate');
        return;
    }
    
    const bridgeSo = path.join(ARTIFACTS_DIR, 'bridge.so');
    if (!fs.existsSync(bridgeSo)) {
        console.log(`❌ bridge.so not found: ${bridgeSo}`);
        console.log('');
        console.log('Build the program first. See contracts/solana/README.md');
        return;
    }
    
    // Check balance
    if (fs.existsSync(KEYPAIR_PATH)) {
        const keypairData = JSON.parse(fs.readFileSync(KEYPAIR_PATH, 'utf-8'));
        const payer = Keypair.fromSecretKey(Uint8Array.from(keypairData));
        const connection = new Connection(SOLANA_RPC, 'confirmed');
        const balance = await connection.getBalance(payer.publicKey);
        console.log(`Deployer: ${payer.publicKey}`);
        console.log(`Balance: ${balance / 1e9} SOL`);
        
        if (balance < 5e9) {
            console.log('');
            console.log('⚠️  Low balance! Get more SOL:');
            console.log(`   solana airdrop 10 ${payer.publicKey} --url ${SOLANA_RPC}`);
        }
    }
    
    console.log('');
    console.log('Deploy command:');
    console.log('');
    console.log(`solana program deploy \\`);
    console.log(`  --program-id ${PROGRAM_ID_FILE} \\`);
    console.log(`  ${bridgeSo} \\`);
    console.log(`  --url ${SOLANA_RPC} \\`);
    console.log(`  --keypair ${KEYPAIR_PATH}`);
    console.log('');
    console.log('After deployment, run: node src/cli/deploy-solana.js initialize');
}

async function initializeProgram() {
    console.log('='.repeat(60));
    console.log('Initialize Solana Wormhole Core Bridge');
    console.log('='.repeat(60));
    console.log('');
    
    // Load program ID
    if (!fs.existsSync(PROGRAM_ID_FILE)) {
        console.log('❌ Program ID not generated');
        console.log('   Run: node src/cli/deploy-solana.js generate');
        process.exit(1);
    }
    
    const programData = JSON.parse(fs.readFileSync(PROGRAM_ID_FILE, 'utf-8'));
    const programKeypair = Keypair.fromSecretKey(Uint8Array.from(programData));
    const programId = programKeypair.publicKey;
    console.log(`Program ID: ${programId}`);
    
    // Load payer keypair
    if (!fs.existsSync(KEYPAIR_PATH)) {
        console.log(`❌ Keypair not found: ${KEYPAIR_PATH}`);
        process.exit(1);
    }
    
    const keypairData = JSON.parse(fs.readFileSync(KEYPAIR_PATH, 'utf-8'));
    const payer = Keypair.fromSecretKey(Uint8Array.from(keypairData));
    console.log(`Payer: ${payer.publicKey}`);
    
    // Connect
    const connection = new Connection(SOLANA_RPC, 'confirmed');
    
    // Check if program is deployed
    const programInfo = await connection.getAccountInfo(programId);
    if (!programInfo) {
        console.log('');
        console.log('❌ Program not deployed yet');
        console.log('   Run: node src/cli/deploy-solana.js deploy');
        process.exit(1);
    }
    
    console.log(`Program deployed ✓ (${programInfo.data.length} bytes)`);
    
    // Check if already initialized
    try {
        const { deriveWormholeBridgeDataKey } = require('@certusone/wormhole-sdk/lib/cjs/solana/wormhole');
        const bridgeDataKey = deriveWormholeBridgeDataKey(programId);
        const bridgeAccountInfo = await connection.getAccountInfo(bridgeDataKey);
        if (bridgeAccountInfo && bridgeAccountInfo.data.length > 0) {
            console.log('');
            console.log('✅ Bridge already initialized!');
            console.log(`   Bridge Data: ${bridgeDataKey}`);
            return;
        }
    } catch (e) {
        // Continue with initialization
    }
    
    // Get guardian set
    const guardians = getGuardianSet();
    console.log(`Guardians: ${guardians.length}`);
    guardians.forEach((g, i) => console.log(`  ${i}: 0x${g}`));
    
    console.log('');
    console.log('Initializing...');
    
    try {
        // Use Wormhole SDK to create initialize instruction
        const { createInitializeInstruction } = require('@certusone/wormhole-sdk/lib/cjs/solana/wormhole/instructions/initialize');
        
        // Convert guardian addresses to Buffers (20 bytes each)
        const guardianBuffers = guardians.map(g => {
            const hex = g.replace(/^0x/i, '');
            if (hex.length !== 40) {
                throw new Error(`Invalid guardian address length: ${g} (expected 40 hex chars)`);
            }
            return Buffer.from(hex, 'hex');
        });
        
        // Initialize parameters
        const guardianSetExpirationTime = 86400; // 24 hours (in seconds)
        const fee = BigInt(0); // 0 lamports fee
        
        // Create instruction
        const initializeIx = createInitializeInstruction(
            programId,
            payer.publicKey,
            guardianSetExpirationTime,
            fee,
            guardianBuffers
        );
        
        // Create and send transaction
        const transaction = new Transaction().add(initializeIx);
        const signature = await sendAndConfirmTransaction(
            connection,
            transaction,
            [payer],
            { commitment: 'confirmed' }
        );
        
        console.log('');
        console.log('='.repeat(60));
        console.log('✅ Solana Core Bridge Initialized!');
        console.log('='.repeat(60));
        console.log(`Program ID: ${programId}`);
        console.log(`Transaction: ${signature}`);
        console.log(`Guardians:   ${guardians.length}`);
        console.log(`Fee:         ${fee} lamports`);
        console.log(`Expiry:      ${guardianSetExpirationTime}s (${guardianSetExpirationTime / 3600}h)`);
        console.log('');
        console.log('Add to config/guardian.conf:');
        console.log(`  SOLANA_CONTRACT="${programId}"`);
        console.log('');
        console.log('The guardian will start watching this program for messages.');
        
    } catch (err) {
        console.error('');
        console.error('❌ Initialization failed:', err.message);
        if (err.logs) {
            console.error('Logs:');
            err.logs.forEach(log => console.error('  ', log));
        }
        process.exit(1);
    }
}

async function main() {
    const command = process.argv[2] || 'status';
    
    switch (command) {
        case 'generate':
        case 'gen':
            await generateProgramId();
            break;
        case 'deploy':
            await showDeployCommand();
            break;
        case 'initialize':
        case 'init':
            await initializeProgram();
            break;
        case 'status':
        default:
            await showStatus();
            break;
    }
}

main().catch(err => {
    console.error('Error:', err.message);
    process.exit(1);
});

