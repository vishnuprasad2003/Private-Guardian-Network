#!/usr/bin/env node
/**
 * Post VAA to Solana CLI Tool
 * 
 * Usage: 
 *   node src/cli/post-vaa-solana.js <chainId> <emitter> <sequence>
 *   node src/cli/post-vaa-solana.js <vaaHex>
 */

const { Connection, Keypair, PublicKey } = require('@solana/web3.js');
const { postVaa } = require('@certusone/wormhole-sdk/lib/cjs/solana/sendAndConfirmPostVaa');
const { derivePostedVaaKey, getPostedVaa } = require('@certusone/wormhole-sdk/lib/cjs/solana/wormhole');
const { parseVaa } = require('@certusone/wormhole-sdk/lib/cjs/vaa/wormhole');
const fs = require('fs');
const path = require('path');
const http = require('http');
const config = require('../lib/config');

const ROOT_DIR = config.ROOT_DIR;
const cfg = config.loadConfig();

// Configuration
const SOLANA_RPC = process.env.SOLANA_RPC || cfg.SOLANA_RPC || 'http://127.0.0.1:8899';
const SOLANA_CONTRACT = process.env.SOLANA_CONTRACT || cfg.SOLANA_CONTRACT;
const KEYPAIR_PATH = process.env.SOLANA_KEYPAIR || path.join(ROOT_DIR, 'keys', 'solana-deployer.json');
const API_URL = process.env.API_URL || 'http://localhost:3000';

const args = process.argv.slice(2);

if (args.length === 0) {
    console.log('Usage:');
    console.log('  node src/cli/post-vaa-solana.js <chainId> <emitter> <sequence>');
    console.log('  node src/cli/post-vaa-solana.js <vaaHex>');
    process.exit(1);
}

async function fetchVAAFromAPI(chainId, emitter, sequence) {
    return new Promise((resolve, reject) => {
        const url = `${API_URL}/api/v1/vaas/${chainId}/${emitter}/${sequence}`;
        
        http.get(url, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                if (res.statusCode === 200) {
                    const json = JSON.parse(data);
                    resolve(json.vaa);
                } else {
                    reject(new Error(`API error ${res.statusCode}: ${data}`));
                }
            });
        }).on('error', reject);
    });
}

function loadKeypair() {
    if (!fs.existsSync(KEYPAIR_PATH)) {
        throw new Error(`Keypair not found: ${KEYPAIR_PATH}`);
    }
    const data = JSON.parse(fs.readFileSync(KEYPAIR_PATH, 'utf-8'));
    return Keypair.fromSecretKey(Uint8Array.from(data));
}

async function main() {
    console.log('='.repeat(60));
    console.log('Post VAA to Solana');
    console.log('='.repeat(60));
    
    // Get VAA hex
    let vaaHex;
    if (args.length === 1) {
        vaaHex = args[0].replace(/^0x/i, '');
        console.log(`Using provided VAA (${vaaHex.length / 2} bytes)`);
    } else {
        const [chainId, emitter, sequence] = args;
        let normalizedEmitter = emitter.replace(/^0x/i, '').padStart(64, '0');
        
        console.log(`Fetching VAA from API...`);
        console.log(`  Chain: ${chainId}, Emitter: ${normalizedEmitter}, Sequence: ${sequence}`);
        
        vaaHex = await fetchVAAFromAPI(chainId, normalizedEmitter, sequence);
        console.log(`✅ VAA fetched (${vaaHex.length / 2} bytes)`);
    }
    
    // Parse VAA
    const vaaBuffer = Buffer.from(vaaHex, 'hex');
    const parsedVaa = parseVaa(vaaBuffer);
    
    console.log('');
    console.log('VAA Details:');
    console.log(`  Emitter Chain: ${parsedVaa.emitterChain}`);
    console.log(`  Sequence: ${parsedVaa.sequence}`);
    console.log(`  Payload: ${Buffer.from(parsedVaa.payload).toString('hex')}`);
    
    // Setup Solana
    if (!SOLANA_CONTRACT) {
        throw new Error('SOLANA_CONTRACT not configured');
    }
    
    const programId = new PublicKey(SOLANA_CONTRACT);
    const payer = loadKeypair();
    const connection = new Connection(SOLANA_RPC, 'confirmed');
    
    console.log('');
    console.log(`Program ID: ${programId}`);
    console.log(`Payer: ${payer.publicKey}`);
    
    // Check balance
    const balance = await connection.getBalance(payer.publicKey);
    console.log(`Balance: ${balance / 1e9} SOL`);
    
    if (balance < 0.1e9) {
        throw new Error('Insufficient balance');
    }
    
    // Post VAA
    console.log('');
    console.log('Posting VAA...');
    
    const signTransaction = async (tx) => {
        tx.partialSign(payer);
        return tx;
    };
    
    const responses = await postVaa(
        connection,
        signTransaction,
        programId,
        payer.publicKey.toString(),
        vaaBuffer,
        { commitment: 'confirmed' }
    );
    
    console.log('');
    console.log('='.repeat(60));
    console.log('✅ VAA Posted Successfully!');
    console.log('='.repeat(60));
    console.log('Transactions:');
    responses.forEach((r, i) => console.log(`  [${i + 1}] ${r.signature}`));
    
    // Read posted VAA
    const vaaKey = derivePostedVaaKey(programId, parsedVaa.hash);
    console.log('');
    console.log(`VAA Account: ${vaaKey}`);
    console.log(`Payload Text: "${Buffer.from(parsedVaa.payload).toString('utf8')}"`);
}

main().catch(error => {
    console.error('Error:', error.message);
    process.exit(1);
});

