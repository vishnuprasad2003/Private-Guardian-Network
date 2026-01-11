#!/usr/bin/env node
/**
 * Fetch VAA CLI Tool
 * 
 * Usage: node src/cli/fetch-vaa.js <chainId> <emitter> <sequence>
 */

const guardiand = require('../lib/guardiand');

const args = process.argv.slice(2);

if (args.length < 3) {
    console.log('Usage: node src/cli/fetch-vaa.js <chainId> <emitter> <sequence>');
    console.log('');
    console.log('Arguments:');
    console.log('  chainId   Wormhole chain ID (e.g., 6 for Avalanche)');
    console.log('  emitter   Emitter address (32-byte hex, no 0x prefix)');
    console.log('  sequence  Message sequence number');
    console.log('');
    console.log('Example:');
    console.log('  node src/cli/fetch-vaa.js 6 000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d 1');
    process.exit(1);
}

const [chainId, emitter, sequence] = args;

// Normalize emitter
let normalizedEmitter = emitter.replace(/^0x/i, '').toLowerCase();
if (normalizedEmitter.length < 64) {
    normalizedEmitter = normalizedEmitter.padStart(64, '0');
}

console.log('='.repeat(60));
console.log('Fetching VAA');
console.log('='.repeat(60));
console.log(`Chain ID: ${chainId}`);
console.log(`Emitter: ${normalizedEmitter}`);
console.log(`Sequence: ${sequence}`);
console.log('');

try {
    const result = guardiand.fetchVAA(chainId, normalizedEmitter, sequence);
    
    if (!result || !result.vaaHex) {
        console.error('VAA not found');
        process.exit(1);
    }
    
    console.log('='.repeat(60));
    console.log('VAA Found');
    console.log('='.repeat(60));
    
    if (result.digest) {
        console.log(`Digest: ${result.digest}`);
    }
    
    if (result.vaaJson) {
        console.log('');
        console.log('Parsed VAA:');
        console.log(JSON.stringify(result.vaaJson, null, 2));
        
        // Decode payload
        if (result.vaaJson.Payload) {
            console.log('');
            console.log('Payload:');
            const buf = Buffer.from(result.vaaJson.Payload, 'base64');
            console.log(`  Hex: 0x${buf.toString('hex')}`);
            const text = buf.toString('utf8');
            if (/^[\x20-\x7E]+$/.test(text)) {
                console.log(`  Text: "${text}"`);
            }
        }
    }
    
    console.log('');
    console.log('='.repeat(60));
    console.log('VAA Hex (for posting to other chains):');
    console.log('='.repeat(60));
    console.log(result.vaaHex);
    
} catch (error) {
    console.error('Error:', error.message);
    process.exit(1);
}

