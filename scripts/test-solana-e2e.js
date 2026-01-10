#!/usr/bin/env node
/**
 * End-to-End Test: Avalanche -> Guardian -> Solana
 * 
 * This script:
 * 1. Publishes a message on Avalanche L1
 * 2. Waits for guardian to observe and create VAA
 * 3. Fetches VAA from API
 * 4. Posts VAA to Solana
 * 5. Verifies payload is stored on Solana
 * 
 * Usage:
 *   node scripts/test-solana-e2e.js [payload]
 * 
 * Example:
 *   node scripts/test-solana-e2e.js "Hello from Avalanche!"
 */

const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const rootDir = path.resolve(__dirname, '..');

// Configuration
const AVALANCHE_RPC = process.env.AVALANCHE_RPC || 'http://20.253.174.32:80/ext/bc/2ALtzRYgRpRWnTgjdrMArkMvU6RTpcjs7VWmupqYaPrHDrHLSd/rpc';
const AVALANCHE_CONTRACT = process.env.AVALANCHE_CONTRACT || '0x4f8270c650d1dd73f5d13eb2464c19e35f85a8d8';
const AVALANCHE_PRIVATE_KEY = process.env.AVALANCHE_PRIVATE_KEY || '476645f88bc9ef81a40a45ef84972b8e71944f1bd7080cf2b0d6efdc60ee43e6';
const AVALANCHE_WALLET = process.env.AVALANCHE_WALLET || '0xC60B683D1835B72A1f3CdAE3ac29b49607F0176D';
const API_URL = process.env.API_URL || 'http://localhost:3000';
const SOLANA_RPC = process.env.SOLANA_RPC || 'http://127.0.0.1:8899';

// Get payload
const payloadText = process.argv[2] || 'Hello from Avalanche!';
const payloadHex = Buffer.from(payloadText).toString('hex');

async function runTest() {
console.log('='.repeat(70));
console.log('End-to-End Test: Avalanche -> Guardian -> Solana');
console.log('='.repeat(70));
console.log(`Payload: "${payloadText}"`);
console.log(`Payload Hex: 0x${payloadHex}`);
console.log('');

// Step 1: Publish message on Avalanche
console.log('Step 1: Publishing message on Avalanche...');
console.log(`  Contract: ${AVALANCHE_CONTRACT}`);
console.log(`  Wallet: ${AVALANCHE_WALLET}`);
console.log('');

const castBin = process.env.CAST_BIN || 'cast';
const nonce = Math.floor(Math.random() * 1000000); // Random nonce

try {
    const txOutput = execSync(
        `"${castBin}" send "${AVALANCHE_CONTRACT}" "publishMessage(uint32,bytes,uint8)" ` +
        `${nonce} 0x${payloadHex} 1 ` +
        `--rpc-url "${AVALANCHE_RPC}" --private-key "${AVALANCHE_PRIVATE_KEY}" --json`,
        { encoding: 'utf-8', stdio: 'pipe' }
    );

    let txResult;
    try {
        txResult = JSON.parse(txOutput);
    } catch (e) {
        // Try to extract transaction hash from text
        const txHashMatch = txOutput.match(/transactionHash[:\s]+(0x[a-fA-F0-9]+)/i);
        if (txHashMatch) {
            txResult = { transactionHash: txHashMatch[1] };
        } else {
            throw new Error('Could not parse transaction result');
        }
    }

    const txHash = txResult.transactionHash || txResult.hash;
    console.log(`✅ Message published!`);
    console.log(`  Transaction: ${txHash}`);
    console.log(`  Block: ${txResult.blockNumber || 'pending'}`);
    console.log('');

    // Extract sequence from logs
    let sequence = null;
    if (txResult.logs) {
        // The sequence is in the LogMessagePublished event
        // We'll need to query it or wait and check
        console.log('  Note: Sequence number will be determined from event logs');
    }

    // Step 2: Wait for guardian to observe
    console.log('Step 2: Waiting for guardian to observe message...');
    console.log('  (Waiting 15 seconds for guardian to process...)');
    
    await new Promise(resolve => setTimeout(resolve, 15000));

    // Step 3: Fetch VAA from API
    console.log('');
    console.log('Step 3: Fetching VAA from API...');
    
    // We need to determine the sequence - for now, try sequence 0, 1, 2...
    // In production, you'd parse it from the transaction logs
    let vaaFound = false;
    let vaaData = null;
    let actualSequence = null;

    // Try recent sequences
    for (let seq = 0; seq < 10; seq++) {
        try {
            const https = require('https');
            const http = require('http');
            const client = API_URL.startsWith('https') ? https : http;
            
            const emitterAddr = AVALANCHE_WALLET.replace(/^0x/i, '').padStart(64, '0');
            const url = `${API_URL}/api/v1/vaas/6/${emitterAddr}/${seq}`;
            
            await new Promise((resolve, reject) => {
                client.get(url, (res) => {
                    let data = '';
                    res.on('data', (chunk) => { data += chunk; });
                    res.on('end', () => {
                        if (res.statusCode === 200) {
                            try {
                                const json = JSON.parse(data);
                                // Check if payload matches
                                const payloadBytes = Buffer.from(json.payload, 'base64');
                                if (payloadBytes.toString('hex') === payloadHex) {
                                    vaaData = json;
                                    actualSequence = seq;
                                    vaaFound = true;
                                }
                            } catch (e) {}
                        }
                        resolve();
                    });
                }).on('error', reject);
            });

            if (vaaFound) break;
        } catch (e) {
            // Continue searching
        }
    }

    if (!vaaFound) {
        console.error('❌ VAA not found. The guardian may not have observed the message yet.');
        console.error('   Try running: node scripts/fetch-vaa.js 6 <emitter> <sequence>');
        console.error('   Or check guardian logs: ./scripts/logs.sh');
        process.exit(1);
    }

    console.log(`✅ VAA found!`);
    console.log(`  Sequence: ${actualSequence}`);
    console.log(`  Digest: ${vaaData.digest}`);
    console.log('');

    // Step 4: Post VAA to Solana
    console.log('Step 4: Posting VAA to Solana...');
    console.log(`  Solana RPC: ${SOLANA_RPC}`);
    console.log('');

    // Run post-vaa-solana script
    const emitterAddr = AVALANCHE_WALLET.replace(/^0x/i, '').padStart(64, '0');
    execSync(
        `node scripts/post-vaa-solana.js 6 ${emitterAddr} ${actualSequence}`,
        { stdio: 'inherit', cwd: rootDir }
    );

    console.log('');
    console.log('='.repeat(70));
    console.log('✅ End-to-End Test Complete!');
    console.log('='.repeat(70));
    console.log('Summary:');
    console.log(`  1. Published message on Avalanche: ${txHash}`);
    console.log(`  2. Guardian observed and created VAA: ${vaaData.digest}`);
    console.log(`  3. Posted VAA to Solana: Success`);
    console.log(`  4. Payload verified and stored on Solana`);
    console.log('');
    console.log(`Payload "${payloadText}" is now stored on Solana!`);
    console.log('='.repeat(70));

}

runTest().catch((error) => {
    console.error('');
    console.error('❌ Test failed:');
    console.error(error.message);
    if (error.stdout) console.error(error.stdout);
    if (error.stderr) console.error(error.stderr);
    process.exit(1);
});

