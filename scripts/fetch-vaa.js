#!/usr/bin/env node
/**
 * Fetch and parse VAA from guardian node
 * Usage: node scripts/fetch-vaa.js <chain_id> <emitter_address> <sequence>
 * Example: node scripts/fetch-vaa.js 6 000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d 1
 */

const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

// Parse command line arguments
const args = process.argv.slice(2);

if (args.length < 3) {
    console.error('Usage: node scripts/fetch-vaa.js <chain_id> <emitter_address> <sequence>');
    console.error('');
    console.error('Arguments:');
    console.error('  chain_id        - Wormhole chain ID (e.g., 6 for Avalanche)');
    console.error('  emitter_address - Emitter address (32-byte hex, no 0x prefix)');
    console.error('  sequence        - Message sequence number');
    console.error('');
    console.error('Example:');
    console.error('  node scripts/fetch-vaa.js 6 000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d 1');
    process.exit(1);
}

const [chainId, emitterAddress, sequence] = args;

// Validate inputs
if (!/^\d+$/.test(chainId)) {
    console.error('Error: chain_id must be a number');
    process.exit(1);
}

if (!/^[0-9a-fA-F]{64}$/.test(emitterAddress)) {
    console.error('Error: emitter_address must be 64 hex characters (32 bytes)');
    process.exit(1);
}

if (!/^\d+$/.test(sequence)) {
    console.error('Error: sequence must be a number');
    process.exit(1);
}

// Build message ID
const messageId = `${chainId}/${emitterAddress}/${sequence}`;

// Find guardiand binary
const rootDir = path.resolve(__dirname, '..');
const guardiandBin = process.env.GUARDIAND_BIN || 
    path.join(rootDir, '..', 'WormHole-Official-GitHub-Repo', 'build', 'bin', 'guardiand');

if (!fs.existsSync(guardiandBin)) {
    console.error(`Error: guardiand binary not found at ${guardiandBin}`);
    console.error('Set GUARDIAND_BIN environment variable or ensure guardiand is built');
    process.exit(1);
}

// Find admin socket
const adminSocket = process.env.ADMIN_SOCKET || 
    path.join(rootDir, 'data', 'guardian-0.sock');

if (!fs.existsSync(adminSocket)) {
    console.error(`Error: Admin socket not found at ${adminSocket}`);
    console.error('Make sure the guardian is running');
    process.exit(1);
}

console.log('='.repeat(70));
console.log('Fetching VAA');
console.log('='.repeat(70));
console.log(`Message ID: ${messageId}`);
console.log(`Admin Socket: ${adminSocket}`);
console.log('');

try {
    // Fetch VAA using guardiand admin command
    // Note: guardiand outputs to stderr (JSON) and stdout (hex)
    // Use 2>&1 to capture both
    const output = execSync(
        `"${guardiandBin}" admin dump-vaa-by-message-id --socket "${adminSocket}" "${messageId}" 2>&1`,
        { encoding: 'utf-8', stdio: 'pipe' }
    );

    // Parse the output
    const lines = output.trim().split('\n');
    
    // Extract VAA hex bytes
    let vaaHex = '';
    let vaaJson = null;
    let digest = '';
    
    // Find "Bytes:" line and extract hex
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        if (line.startsWith('Bytes:')) {
            // Next line should be the hex
            if (i + 1 < lines.length) {
                vaaHex = lines[i + 1].trim();
            }
        }
        
        // Find "VAA with digest" line
        if (line.includes('VAA with digest')) {
            // Extract digest
            const match = line.match(/digest ([a-f0-9]+):/);
            if (match) {
                digest = match[1];
            }
            
            // Find the opening brace (should be on same line after colon)
            const colonIndex = line.indexOf(':');
            const braceIndex = line.indexOf('{', colonIndex);
            
            if (braceIndex === -1) {
                continue; // Skip if no opening brace found
            }
            
            // Extract JSON starting from the opening brace
            let jsonText = line.substring(braceIndex);
            let braceCount = 1;
            let jsonEnd = i;
            
            // Continue reading lines until we find the closing brace
            for (let j = i + 1; j < lines.length; j++) {
                const l = lines[j];
                const openBraces = (l.match(/{/g) || []).length;
                const closeBraces = (l.match(/}/g) || []).length;
                
                jsonText += '\n' + l;
                braceCount += openBraces - closeBraces;
                
                if (braceCount === 0) {
                    jsonEnd = j;
                    break;
                }
            }
            
            // Parse JSON
            if (braceCount === 0) {
                try {
                    vaaJson = JSON.parse(jsonText);
                } catch (e) {
                    // Try to extract just the JSON object
                    const jsonMatch = jsonText.match(/\{[\s\S]*\}/);
                    if (jsonMatch) {
                        try {
                            vaaJson = JSON.parse(jsonMatch[0]);
                        } catch (e2) {
                            console.warn('Warning: Could not parse VAA JSON:', e2.message);
                        }
                    }
                }
            }
        }
    }

    // Display results
    console.log('='.repeat(70));
    console.log('VAA Details');
    console.log('='.repeat(70));
    
    if (digest) {
        console.log(`Digest: ${digest}`);
        console.log('');
    }
    
    if (vaaJson) {
        console.log('Parsed VAA:');
        console.log(JSON.stringify(vaaJson, null, 2));
        console.log('');
        
        // Decode payload if present
        if (vaaJson.Payload) {
            try {
                const payloadBytes = Buffer.from(vaaJson.Payload, 'base64');
                const payloadHex = payloadBytes.toString('hex');
                const payloadText = payloadBytes.toString('utf8');
                
                console.log('Payload:');
                console.log(`  Base64: ${vaaJson.Payload}`);
                console.log(`  Hex:    0x${payloadHex}`);
                
                // Try to decode as text
                if (/^[\x20-\x7E]+$/.test(payloadText)) {
                    console.log(`  Text:   "${payloadText}"`);
                } else {
                    console.log(`  Raw:    ${payloadText}`);
                }
                console.log('');
            } catch (e) {
                console.log(`  Payload: ${vaaJson.Payload} (could not decode)`);
            }
        }
        
        // Display signature info
        if (vaaJson.Signatures && vaaJson.Signatures.length > 0) {
            console.log('Signatures:');
            vaaJson.Signatures.forEach((sig, idx) => {
                console.log(`  [${idx}] Guardian Index: ${sig.Index}`);
                console.log(`      Signature: ${sig.Signature}`);
            });
            console.log('');
        }
        
        // Display emitter info
        console.log('Emitter:');
        console.log(`  Chain ID: ${vaaJson.EmitterChain}`);
        console.log(`  Address:  0x${vaaJson.EmitterAddress}`);
        console.log(`  Sequence: ${vaaJson.Sequence}`);
        console.log('');
    }
    
    if (vaaHex) {
        console.log('='.repeat(70));
        console.log('VAA Hex (for posting to other chains):');
        console.log('='.repeat(70));
        console.log(vaaHex);
        console.log('');
    }
    
    console.log('='.repeat(70));
    console.log('Success!');
    console.log('='.repeat(70));
    
} catch (error) {
    console.error('='.repeat(70));
    console.error('Error fetching VAA');
    console.error('='.repeat(70));
    console.error(error.message);
    
    if (error.stderr) {
        console.error('\nStderr:');
        console.error(error.stderr);
    }
    
    if (error.stdout) {
        console.error('\nStdout:');
        console.error(error.stdout);
    }
    
    process.exit(1);
}

