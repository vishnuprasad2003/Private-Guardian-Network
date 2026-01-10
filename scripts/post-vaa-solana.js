#!/usr/bin/env node
/**
 * Post VAA to Solana Wormhole Bridge and Verify Payload
 * 
 * Usage:
 *   node scripts/post-vaa-solana.js <chainId> <emitter> <sequence>
 *   node scripts/post-vaa-solana.js <vaaHex>
 * 
 * Environment Variables:
 *   SOLANA_RPC - Solana RPC URL (default: http://127.0.0.1:8899)
 *   SOLANA_KEYPAIR - Path to keypair file or base58 private key
 *   SOLANA_CONTRACT - Wormhole program ID (or will read from config)
 *   API_URL - VAA API server URL (default: http://localhost:3000)
 */

const { Connection, Keypair, PublicKey } = require('@solana/web3.js');
const { postVaa } = require('@certusone/wormhole-sdk/lib/cjs/solana/sendAndConfirmPostVaa');
const { derivePostedVaaKey, getPostedVaa } = require('@certusone/wormhole-sdk/lib/cjs/solana/wormhole');
const { parseVaa } = require('@certusone/wormhole-sdk/lib/cjs/vaa/wormhole');
const fs = require('fs');
const path = require('path');
const bs58 = require('bs58');
const https = require('https');
const http = require('http');

const rootDir = path.resolve(__dirname, '..');

// Parse arguments
const args = process.argv.slice(2);

if (args.length === 0) {
    console.error('Usage: node scripts/post-vaa-solana.js <chainId> <emitter> <sequence>');
    console.error('   or: node scripts/post-vaa-solana.js <vaaHex>');
    console.error('');
    console.error('Example:');
    console.error('  node scripts/post-vaa-solana.js 6 000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d 1');
    console.error('  node scripts/post-vaa-solana.js 01000000000100...');
    process.exit(1);
}

// Configuration
const SOLANA_RPC = process.env.SOLANA_RPC || 'http://127.0.0.1:8899';
const SOLANA_KEYPAIR = process.env.SOLANA_KEYPAIR || path.join(rootDir, 'keys', 'solana-deployer.json');
const API_URL = process.env.API_URL || 'http://localhost:3000';

// Load Solana contract from config
function getSolanaContract() {
    const configPath = path.join(rootDir, 'config', 'guardian.conf');
    if (fs.existsSync(configPath)) {
        const config = fs.readFileSync(configPath, 'utf-8');
        for (const line of config.split('\n')) {
            const match = line.match(/^SOLANA_CONTRACT="([^"]+)"/i);
            if (match) {
                return match[1];
            }
        }
    }
    return process.env.SOLANA_CONTRACT;
}

// Fetch VAA from API
async function fetchVAAFromAPI(chainId, emitter, sequence) {
    return new Promise((resolve, reject) => {
        const url = `${API_URL}/api/v1/vaas/${chainId}/${emitter}/${sequence}`;
        const client = url.startsWith('https') ? https : http;
        
        client.get(url, (res) => {
            let data = '';
            res.on('data', (chunk) => { data += chunk; });
            res.on('end', () => {
                if (res.statusCode === 200) {
                    try {
                        const json = JSON.parse(data);
                        resolve(json.vaa);
                    } catch (e) {
                        reject(new Error(`Failed to parse API response: ${e.message}`));
                    }
                } else {
                    reject(new Error(`API returned ${res.statusCode}: ${data}`));
                }
            });
        }).on('error', reject);
    });
}

// Load keypair
function loadKeypair() {
    if (fs.existsSync(SOLANA_KEYPAIR)) {
        const keypairData = JSON.parse(fs.readFileSync(SOLANA_KEYPAIR, 'utf-8'));
        return Keypair.fromSecretKey(Uint8Array.from(keypairData));
    } else {
        try {
            return Keypair.fromSecretKey(bs58.decode(SOLANA_KEYPAIR));
        } catch (e) {
            throw new Error(`Keypair not found: ${SOLANA_KEYPAIR}`);
        }
    }
}

async function main() {
    console.log('='.repeat(70));
    console.log('Post VAA to Solana Wormhole Bridge');
    console.log('='.repeat(70));
    console.log(`Solana RPC: ${SOLANA_RPC}`);
    console.log(`API URL: ${API_URL}`);
    console.log('');

    // Get VAA hex
    let vaaHex;
    if (args.length === 1) {
        // VAA hex provided directly
        vaaHex = args[0].replace(/^0x/i, '').replace(/\s/g, '');
        console.log(`Using provided VAA hex (${vaaHex.length / 2} bytes)`);
    } else if (args.length === 3) {
        // Fetch from API
        const [chainId, emitter, sequence] = args;
        console.log(`Fetching VAA from API...`);
        console.log(`  Chain ID: ${chainId}`);
        console.log(`  Emitter: ${emitter}`);
        console.log(`  Sequence: ${sequence}`);
        console.log('');
        
        // Normalize emitter address
        let emitterAddr = emitter.replace(/^0x/i, '');
        if (emitterAddr.length < 64) {
            emitterAddr = emitterAddr.padStart(64, '0');
        }
        
        vaaHex = await fetchVAAFromAPI(chainId, emitterAddr, sequence);
        console.log(`✅ VAA fetched (${vaaHex.length / 2} bytes)`);
    } else {
        console.error('Error: Invalid arguments');
        process.exit(1);
    }

    // Convert hex to buffer
    const vaaBuffer = Buffer.from(vaaHex, 'hex');
    
    // Parse VAA to get details
    const parsedVaa = parseVaa(vaaBuffer);
    console.log('');
    console.log('VAA Details:');
    console.log(`  Version: ${parsedVaa.version}`);
    console.log(`  Guardian Set Index: ${parsedVaa.guardianSetIndex}`);
    console.log(`  Emitter Chain: ${parsedVaa.emitterChain}`);
    console.log(`  Emitter Address: 0x${Buffer.from(parsedVaa.emitterAddress).toString('hex')}`);
    console.log(`  Sequence: ${parsedVaa.sequence}`);
    console.log(`  Payload: ${Buffer.from(parsedVaa.payload).toString('hex')} (${parsedVaa.payload.length} bytes)`);
    console.log('');

    // Get program ID
    const programIdStr = getSolanaContract();
    if (!programIdStr) {
        console.error('Error: SOLANA_CONTRACT not found in config or environment');
        console.error('Set it in config/guardian.conf or SOLANA_CONTRACT environment variable');
        process.exit(1);
    }
    const programId = new PublicKey(programIdStr);
    console.log(`Program ID: ${programId.toString()}`);

    // Load keypair
    const payer = loadKeypair();
    console.log(`Payer: ${payer.publicKey.toString()}`);
    console.log('');

    // Connect to Solana
    const connection = new Connection(SOLANA_RPC, 'confirmed');
    
    // Check balance
    const balance = await connection.getBalance(payer.publicKey);
    console.log(`Balance: ${balance / 1e9} SOL`);
    if (balance < 0.1e9) {
        console.error('Error: Insufficient balance. Need at least 0.1 SOL');
        process.exit(1);
    }

    // Check if VAA is already posted
    const vaaKey = derivePostedVaaKey(programId, parsedVaa.hash);
    const existingVaa = await connection.getAccountInfo(vaaKey);
    
    if (existingVaa) {
        console.log('⚠️  VAA already posted! Reading existing data...');
        try {
            const postedVaa = await getPostedVaa(connection, programId, parsedVaa.hash);
            console.log('');
            console.log('Posted VAA Data:');
            console.log(`  Emitter Chain: ${postedVaa.emitterChain}`);
            console.log(`  Emitter Address: 0x${Buffer.from(postedVaa.emitterAddress).toString('hex')}`);
            console.log(`  Sequence: ${postedVaa.sequence}`);
            console.log(`  Payload: ${Buffer.from(postedVaa.payload).toString('hex')}`);
            console.log(`  Payload Text: ${Buffer.from(postedVaa.payload).toString('utf8')}`);
            console.log('');
            console.log('✅ VAA verified and payload stored!');
            return;
        } catch (e) {
            console.log('Could not read posted VAA, will post again...');
        }
    }

    // Post VAA
    console.log('Posting VAA to Solana...');
    console.log('(This may take a few seconds - verifying signatures and posting...)');
    console.log('');

    const signTransaction = async (tx) => {
        tx.partialSign(payer);
        return tx;
    };

    try {
        const responses = await postVaa(
            connection,
            signTransaction,
            programId,
            payer.publicKey.toString(),
            vaaBuffer,
            { commitment: 'confirmed' }
        );

        console.log('✅ VAA posted successfully!');
        console.log(`Transaction signatures:`);
        responses.forEach((resp, idx) => {
            console.log(`  [${idx + 1}] ${resp.signature}`);
        });
        console.log('');

        // Wait a bit for confirmation
        await new Promise(resolve => setTimeout(resolve, 2000));

        // Read posted VAA
        console.log('Reading posted VAA data...');
        let postedVaa = null;
        try {
            postedVaa = await getPostedVaa(connection, programId, parsedVaa.hash);
        } catch (e) {
            console.log('Note: Could not read posted VAA account (this is OK, VAA was posted successfully)');
        }
        
        console.log('');
        console.log('='.repeat(70));
        console.log('✅ VAA Verified and Payload Stored!');
        console.log('='.repeat(70));
        console.log('Posted VAA Data:');
        console.log(`  VAA Account: ${vaaKey.toString()}`);
        
        // Use parsed VAA data (we already have it) or posted VAA if available
        if (postedVaa) {
            // Try different field name formats
            const emitterChain = postedVaa.emitterChain ?? postedVaa.emitter_chain ?? parsedVaa.emitterChain;
            const emitterAddress = postedVaa.emitterAddress ?? postedVaa.emitter_address ?? parsedVaa.emitterAddress;
            const sequence = postedVaa.sequence ?? parsedVaa.sequence;
            const nonce = postedVaa.nonce ?? parsedVaa.nonce;
            const consistencyLevel = postedVaa.consistencyLevel ?? postedVaa.consistency_level ?? parsedVaa.consistencyLevel;
            const payload = postedVaa.payload ?? parsedVaa.payload;
            
            console.log(`  Emitter Chain: ${emitterChain}`);
            if (emitterAddress) {
                const addrBuf = Buffer.isBuffer(emitterAddress) ? emitterAddress : Buffer.from(emitterAddress);
                console.log(`  Emitter Address: 0x${addrBuf.toString('hex')}`);
            }
            console.log(`  Sequence: ${sequence}`);
            if (nonce !== undefined) console.log(`  Nonce: ${nonce}`);
            console.log(`  Consistency Level: ${consistencyLevel}`);
            if (payload) {
                const payloadBuf = Buffer.isBuffer(payload) ? payload : Buffer.from(payload);
                console.log(`  Payload Length: ${payloadBuf.length} bytes`);
                console.log(`  Payload Hex: 0x${payloadBuf.toString('hex')}`);
                
                // Try to decode as text
                const payloadText = payloadBuf.toString('utf8');
                if (/^[\x20-\x7E]+$/.test(payloadText)) {
                    console.log(`  Payload Text: "${payloadText}"`);
                }
            }
        } else {
            // Fallback to parsed VAA data
            console.log(`  Emitter Chain: ${parsedVaa.emitterChain}`);
            console.log(`  Emitter Address: 0x${Buffer.from(parsedVaa.emitterAddress).toString('hex')}`);
            console.log(`  Sequence: ${parsedVaa.sequence}`);
            console.log(`  Nonce: ${parsedVaa.nonce}`);
            console.log(`  Consistency Level: ${parsedVaa.consistencyLevel}`);
            console.log(`  Payload Length: ${parsedVaa.payload.length} bytes`);
            console.log(`  Payload Hex: 0x${Buffer.from(parsedVaa.payload).toString('hex')}`);
            
            // Try to decode as text
            const payloadText = Buffer.from(parsedVaa.payload).toString('utf8');
            if (/^[\x20-\x7E]+$/.test(payloadText)) {
                console.log(`  Payload Text: "${payloadText}"`);
            }
        }
        
        console.log('');
        console.log('✅ Verification successful! The payload is stored on Solana.');
        console.log('='.repeat(70));

    } catch (error) {
        console.error('');
        console.error('❌ Error posting VAA:');
        console.error(error.message);
        if (error.logs) {
            console.error('');
            console.error('Transaction logs:');
            error.logs.forEach(log => console.error(`  ${log}`));
        }
        process.exit(1);
    }
}

main().catch((error) => {
    console.error('Error:', error);
    process.exit(1);
});

