/**
 * Guardiand CLI Wrapper
 * Interacts with guardiand admin commands
 */

const { execSync } = require('child_process');
const fs = require('fs');
const config = require('./config');

/**
 * Execute guardiand admin command
 * @param {string} command - Admin command
 * @param {string[]} args - Command arguments
 * @returns {string} Command output
 */
function exec(command, args = []) {
    const paths = config.getPaths();
    
    if (!fs.existsSync(paths.guardiand)) {
        throw new Error(`guardiand not found at ${paths.guardiand}`);
    }
    
    if (!fs.existsSync(paths.adminSocket)) {
        throw new Error(`Admin socket not found at ${paths.adminSocket}. Is guardian running?`);
    }
    
    const cmd = `"${paths.guardiand}" admin ${command} --socket "${paths.adminSocket}" ${args.join(' ')}`;
    
    try {
        return execSync(cmd, { encoding: 'utf-8', stdio: 'pipe' });
    } catch (error) {
        if (error.stderr) {
            throw new Error(error.stderr);
        }
        throw error;
    }
}

/**
 * Fetch VAA by message ID
 * @param {number} chainId - Wormhole chain ID
 * @param {string} emitter - Emitter address (32-byte hex)
 * @param {number} sequence - Message sequence
 * @returns {Object} VAA data
 */
function fetchVAA(chainId, emitter, sequence) {
    const messageId = `${chainId}/${emitter}/${sequence}`;
    
    try {
        const output = exec('dump-vaa-by-message-id', [`"${messageId}"`]);
        return parseVAAOutput(output);
    } catch (error) {
        // Handle "not found" errors gracefully
        const errMsg = error.message || error.toString();
        if (errMsg.includes('not found') || 
            errMsg.includes('NotFound') ||
            errMsg.includes('no VAA') ||
            errMsg.includes('Command failed')) {
            return null;
        }
        throw error;
    }
}

/**
 * Parse VAA output from guardiand
 * @param {string} output - Raw output
 * @returns {Object} Parsed VAA
 */
function parseVAAOutput(output) {
    const lines = output.trim().split('\n');
    let vaaHex = '';
    let vaaJson = null;
    let digest = '';
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        if (line.startsWith('Bytes:') && i + 1 < lines.length) {
            vaaHex = lines[i + 1].trim();
        }
        
        if (line.includes('VAA with digest')) {
            const match = line.match(/digest ([a-f0-9]+):/);
            if (match) digest = match[1];
            
            const braceIndex = line.indexOf('{');
            if (braceIndex !== -1) {
                let jsonText = line.substring(braceIndex);
                let braceCount = 1;
                
                for (let j = i + 1; j < lines.length && braceCount > 0; j++) {
                    jsonText += '\n' + lines[j];
                    braceCount += (lines[j].match(/{/g) || []).length;
                    braceCount -= (lines[j].match(/}/g) || []).length;
                }
                
                try {
                    vaaJson = JSON.parse(jsonText);
                } catch (e) {
                    // Ignore parse errors
                }
            }
        }
    }
    
    return { vaaHex, vaaJson, digest };
}

/**
 * Check if guardian is running
 * @returns {boolean}
 */
function isRunning() {
    const paths = config.getPaths();
    return fs.existsSync(paths.adminSocket);
}

module.exports = {
    exec,
    fetchVAA,
    isRunning,
};

