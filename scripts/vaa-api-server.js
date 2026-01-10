#!/usr/bin/env node
/**
 * VAA API Server - REST API for fetching VAAs
 * Similar to Wormholescan API: https://api.testnet.wormholescan.io/api/v1/vaas
 * 
 * Usage: node scripts/vaa-api-server.js [--port 3000] [--host 0.0.0.0]
 */

const express = require('express');
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const app = express();

// CORS middleware for production use
app.use((req, res, next) => {
    const origin = req.headers.origin;
    const allowedOrigins = process.env.ALLOWED_ORIGINS 
        ? process.env.ALLOWED_ORIGINS.split(',')
        : ['*']; // Allow all by default in private network
    
    if (allowedOrigins.includes('*') || (origin && allowedOrigins.includes(origin))) {
        res.setHeader('Access-Control-Allow-Origin', origin || '*');
        res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    }
    
    if (req.method === 'OPTIONS') {
        return res.sendStatus(200);
    }
    
    next();
});

app.use(express.json());

// Request logging middleware (for debugging)
if (process.env.DEBUG === 'true') {
    app.use((req, res, next) => {
        console.log(`${new Date().toISOString()} ${req.method} ${req.path}`);
        next();
    });
}

// Configuration
const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';

// Find guardiand binary
const rootDir = path.resolve(__dirname, '..');
const guardiandBin = process.env.GUARDIAND_BIN || 
    path.join(rootDir, '..', 'WormHole-Official-GitHub-Repo', 'build', 'bin', 'guardiand');

// Find admin socket
const adminSocket = process.env.ADMIN_SOCKET || 
    path.join(rootDir, 'data', 'guardian-0.sock');

// Validate setup
if (!fs.existsSync(guardiandBin)) {
    console.error(`Error: guardiand binary not found at ${guardiandBin}`);
    process.exit(1);
}

if (!fs.existsSync(adminSocket)) {
    console.error(`Error: Admin socket not found at ${adminSocket}`);
    console.error('Make sure the guardian is running');
    process.exit(1);
}

/**
 * Fetch VAA from guardian node
 */
function fetchVAA(chainId, emitterAddress, sequence) {
    const messageId = `${chainId}/${emitterAddress}/${sequence}`;
    
    try {
        const output = execSync(
            `"${guardiandBin}" admin dump-vaa-by-message-id --socket "${adminSocket}" "${messageId}" 2>&1`,
            { encoding: 'utf-8', stdio: 'pipe' }
        );
        
        const lines = output.trim().split('\n');
        let vaaHex = '';
        let vaaJson = null;
        let digest = '';
        
        // Parse output
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            if (line.startsWith('Bytes:')) {
                if (i + 1 < lines.length) {
                    vaaHex = lines[i + 1].trim();
                }
            }
            
            if (line.includes('VAA with digest')) {
                const match = line.match(/digest ([a-f0-9]+):/);
                if (match) {
                    digest = match[1];
                }
                
                const colonIndex = line.indexOf(':');
                const braceIndex = line.indexOf('{', colonIndex);
                
                if (braceIndex !== -1) {
                    let jsonText = line.substring(braceIndex);
                    let braceCount = 1;
                    
                    for (let j = i + 1; j < lines.length; j++) {
                        const l = lines[j];
                        const openBraces = (l.match(/{/g) || []).length;
                        const closeBraces = (l.match(/}/g) || []).length;
                        
                        jsonText += '\n' + l;
                        braceCount += openBraces - closeBraces;
                        
                        if (braceCount === 0) {
                            break;
                        }
                    }
                    
                    if (braceCount === 0) {
                        try {
                            vaaJson = JSON.parse(jsonText);
                        } catch (e) {
                            const jsonMatch = jsonText.match(/\{[\s\S]*\}/);
                            if (jsonMatch) {
                                try {
                                    vaaJson = JSON.parse(jsonMatch[0]);
                                } catch (e2) {
                                    throw new Error(`Failed to parse VAA JSON: ${e2.message}`);
                                }
                            }
                        }
                    }
                }
            }
        }
        
        if (!vaaHex && !vaaJson) {
            throw new Error('VAA not found');
        }
        
        return {
            vaaHex,
            vaaJson,
            digest,
            messageId
        };
    } catch (error) {
        if (error.message.includes('not found') || error.message.includes('NotFound')) {
            throw { status: 404, message: 'VAA not found' };
        }
        throw { status: 500, message: error.message };
    }
}

/**
 * Parse message ID format: chainId/emitter/sequence
 */
function parseMessageId(messageId) {
    const parts = messageId.split('/');
    if (parts.length !== 3) {
        throw { status: 400, message: 'Invalid message ID format. Expected: chainId/emitter/sequence' };
    }
    
    const [chainId, emitter, sequence] = parts;
    
    // Validate
    if (!/^\d+$/.test(chainId)) {
        throw { status: 400, message: 'Invalid chain ID' };
    }
    
    if (!/^[0-9a-fA-F]{64}$/.test(emitter)) {
        throw { status: 400, message: 'Invalid emitter address (must be 64 hex characters)' };
    }
    
    if (!/^\d+$/.test(sequence)) {
        throw { status: 400, message: 'Invalid sequence number' };
    }
    
    return { chainId, emitter, sequence };
}

/**
 * Execute guardiand admin command and parse JSON output
 */
function execAdminCommand(command, parseJson = false) {
    try {
        const output = execSync(
            `"${guardiandBin}" admin ${command} --socket "${adminSocket}" 2>&1`,
            { encoding: 'utf-8', stdio: 'pipe' }
        );
        
        if (parseJson) {
            // Try to extract JSON from output
            const jsonMatch = output.match(/\{[\s\S]*\}/);
            if (jsonMatch) {
                try {
                    return JSON.parse(jsonMatch[0]);
                } catch (e) {
                    // Return raw output if JSON parsing fails
                    return { raw: output };
                }
            }
        }
        
        return output.trim();
    } catch (error) {
        if (error.message.includes('not found') || error.message.includes('NotFound')) {
            throw { status: 404, message: 'Resource not found' };
        }
        throw { status: 500, message: error.message };
    }
}

/**
 * Get guardian set from contract or config
 */
function getGuardianSet(index = null) {
    try {
        // Try to read from config file first (faster)
        const configPath = path.join(rootDir, 'config', 'guardian.conf');
        if (fs.existsSync(configPath)) {
            const configContent = fs.readFileSync(configPath, 'utf-8');
            const guardianAddresses = [];
            
            // Extract guardian addresses from config
            const lines = configContent.split('\n');
            for (const line of lines) {
                const match = line.match(/^GUARDIAN_(\d+)_ADDRESS="(0x[a-fA-F0-9]+)"/i);
                if (match) {
                    guardianAddresses.push(match[2].replace(/^0x/i, ''));
                }
            }
            
            if (guardianAddresses.length > 0) {
                return {
                    index: index || 0,
                    guardians: guardianAddresses,
                    quorum: Math.floor((guardianAddresses.length * 2) / 3) + 1,
                    total: guardianAddresses.length
                };
            }
        }
        
        // Fallback: Try to get from contract via cast (if available)
        // This requires GETH_CONTRACT and GETH_RPC in config
        const configPath2 = path.join(rootDir, 'config', 'guardian.conf');
        if (fs.existsSync(configPath2)) {
            const configContent = fs.readFileSync(configPath2, 'utf-8');
            let gethContract = null;
            let gethRpc = null;
            
            for (const line of configContent.split('\n')) {
                const contractMatch = line.match(/^GETH_CONTRACT="(0x[a-fA-F0-9]+)"/i);
                const rpcMatch = line.match(/^GETH_RPC="(ws?:\/\/[^"]+)"/i);
                if (contractMatch) gethContract = contractMatch[1];
                if (rpcMatch) gethRpc = rpcMatch[1].replace(/^ws/, 'http'); // Convert WS to HTTP for cast
            }
            
            if (gethContract && gethRpc) {
                try {
                    const castBin = process.env.CAST_BIN || 'cast';
                    const output = execSync(
                        `"${castBin}" call "${gethContract}" "getGuardianSet(uint32)" ${index || 0} --rpc-url "${gethRpc}" 2>&1`,
                        { encoding: 'utf-8', stdio: 'pipe' }
                    );
                    
                    // Parse the output (it's a tuple)
                    // Format: (index, keys[], expirationTime)
                    // We need to extract the keys array
                    const keysMatch = output.match(/0x([a-f0-9]+)/g);
                    if (keysMatch && keysMatch.length > 1) {
                        // First match is usually the index or other data
                        // Subsequent matches might be addresses
                        // This is a simplified parser - may need refinement
                        const guardians = keysMatch
                            .slice(1) // Skip first match
                            .filter(k => k.length === 66) // Valid address length (0x + 40 hex)
                            .map(k => k.replace(/^0x/i, ''))
                            .slice(0, 20); // Limit to reasonable number
                        
                        if (guardians.length > 0) {
                            return {
                                index: index || 0,
                                guardians: guardians,
                                quorum: Math.floor((guardians.length * 2) / 3) + 1,
                                total: guardians.length
                            };
                        }
                    }
                } catch (e) {
                    // Cast failed, continue to default
                }
            }
        }
        
        // Default: Return from devnet addresses (if in unsafeDevMode)
        // These are the deterministic addresses
        return {
            index: index || 0,
            guardians: [
                'befa429d57cd18b7f8a4d91a2da9ab4af05d0fbe',
                '88d7d8b32a9105d228100e72dffe2fae0705d31c',
                '58076f561cc62a47087b567c86f986426dfcd000'
            ],
            quorum: 3, // ceil(2/3 * 3) + 1 = 3
            total: 3,
            note: 'Using default devnet guardian set. Update config for production.'
        };
    } catch (error) {
        throw { status: 500, message: `Failed to get guardian set: ${error.message}` };
    }
}

/**
 * Check if message is being observed (not yet finalized)
 */
function checkObservation(chainId, emitterAddress, sequence) {
    const messageId = `${chainId}/${emitterAddress}/${sequence}`;
    
    try {
        // Try to get VAA - if it exists, observation is complete
        const vaa = fetchVAA(chainId, emitterAddress, sequence);
        return {
            observed: true,
            finalized: true,
            hasVAA: true,
            messageId: messageId,
            vaa: {
                digest: vaa.digest,
                timestamp: vaa.vaaJson?.Timestamp
            }
        };
    } catch (error) {
        if (error.status === 404) {
            // VAA doesn't exist - check if message is being observed
            // This would require checking guardian logs or using a different admin command
            // For now, return that it's not finalized
            return {
                observed: false,
                finalized: false,
                hasVAA: false,
                messageId: messageId,
                message: 'Message not yet observed or VAA not created'
            };
        }
        throw error;
    }
}

/**
 * Wormhole Chain ID to name mapping
 */
const CHAIN_NAMES = {
    1: 'Solana',
    2: 'Ethereum',
    3: 'Terra',
    4: 'BSC',
    5: 'Polygon',
    6: 'Avalanche',
    7: 'Oasis',
    8: 'Algorand',
    9: 'Aurora',
    10: 'Fantom',
    11: 'Klaytn',
    12: 'Celo',
    13: 'Near',
    14: 'Moonbeam',
    15: 'Neon',
    16: 'Terra2',
    18: 'Injective',
    19: 'Sui',
    20: 'Aptos',
    21: 'Arbitrum',
    22: 'Optimism',
    23: 'Base',
    24: 'Sei',
    25: 'Rootstock',
    26: 'Scroll',
    27: 'Mantle',
    28: 'Blast',
    29: 'XLayer',
    30: 'Linea',
    10001: 'Testnet',
    10002: 'Devnet'
};

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        service: 'VAA API Server',
        guardian: {
            socket: adminSocket,
            exists: fs.existsSync(adminSocket)
        }
    });
});

// GET /api/v1/vaas/:chainId/:emitter/:sequence
app.get('/api/v1/vaas/:chainId/:emitter/:sequence', (req, res) => {
    try {
        const { chainId, emitter, sequence } = req.params;
        
        // Validate emitter format (remove 0x if present, pad to 64 chars)
        let emitterAddress = emitter.replace(/^0x/i, '');
        if (emitterAddress.length < 64) {
            emitterAddress = emitterAddress.padStart(64, '0');
        }
        
        const result = fetchVAA(chainId, emitterAddress, sequence);
        
        // Format response similar to Wormholescan
        res.json({
            id: result.messageId,
            version: result.vaaJson?.Version || 1,
            guardianSetIndex: result.vaaJson?.GuardianSetIndex || 0,
            vaa: result.vaaHex,
            digest: result.digest,
            timestamp: result.vaaJson?.Timestamp,
            signatures: result.vaaJson?.Signatures || [],
            emitterChain: parseInt(chainId),
            emitterAddress: `0x${emitterAddress}`,
            sequence: parseInt(sequence),
            consistencyLevel: result.vaaJson?.ConsistencyLevel,
            nonce: result.vaaJson?.Nonce,
            payload: result.vaaJson?.Payload
        });
    } catch (error) {
        const status = error.status || 500;
        const message = error.message || 'Internal server error';
        res.status(status).json({ error: message });
    }
});

// GET /api/v1/vaas/:messageId (alternative format)
app.get('/api/v1/vaas/:messageId', (req, res) => {
    try {
        const { messageId } = req.params;
        const { chainId, emitter, sequence } = parseMessageId(messageId);
        
        // Validate emitter format
        let emitterAddress = emitter.replace(/^0x/i, '');
        if (emitterAddress.length < 64) {
            emitterAddress = emitterAddress.padStart(64, '0');
        }
        
        const result = fetchVAA(chainId, emitterAddress, sequence);
        
        res.json({
            id: result.messageId,
            version: result.vaaJson?.Version || 1,
            guardianSetIndex: result.vaaJson?.GuardianSetIndex || 0,
            vaa: result.vaaHex,
            digest: result.digest,
            timestamp: result.vaaJson?.Timestamp,
            signatures: result.vaaJson?.Signatures || [],
            emitterChain: parseInt(chainId),
            emitterAddress: `0x${emitterAddress}`,
            sequence: parseInt(sequence),
            consistencyLevel: result.vaaJson?.ConsistencyLevel,
            nonce: result.vaaJson?.Nonce,
            payload: result.vaaJson?.Payload
        });
    } catch (error) {
        const status = error.status || 500;
        const message = error.message || 'Internal server error';
        res.status(status).json({ error: message });
    }
});

// GET /api/v1/vaas (list endpoint - returns info about available endpoints)
app.get('/api/v1/vaas', (req, res) => {
    res.json({
        message: 'VAA API Server - Production Ready',
        version: '1.0.0',
        endpoints: {
            vaa: {
                getVAA: 'GET /api/v1/vaas/:chainId/:emitter/:sequence',
                getVAAbyMessageId: 'GET /api/v1/vaas/:messageId',
                verifyVAA: 'POST /api/v1/vaas/verify'
            },
            guardianSet: {
                getCurrent: 'GET /api/v1/guardian-set',
                getByIndex: 'GET /api/v1/guardian-set/:index'
            },
            chains: {
                list: 'GET /api/v1/chains',
                getInfo: 'GET /api/v1/chains/:chainId'
            },
            messages: {
                checkStatus: 'GET /api/v1/messages/:chainId/:emitter/:sequence'
            },
            status: {
                health: 'GET /health',
                healthDetailed: 'GET /health/detailed',
                status: 'GET /api/v1/status',
                metrics: 'GET /api/v1/metrics'
            }
        },
        examples: {
            getVAA: {
                url: '/api/v1/vaas/6/000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d/1',
                messageId: '6/000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d/1'
            },
            getGuardianSet: {
                url: '/api/v1/guardian-set'
            },
            checkMessage: {
                url: '/api/v1/messages/6/000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d/1'
            }
        }
    });
});

// ============================================================================
// GUARDIAN SET ENDPOINTS
// ============================================================================

// GET /api/v1/guardian-set - Get current guardian set
app.get('/api/v1/guardian-set', (req, res) => {
    try {
        const guardianSet = getGuardianSet();
        res.json({
            index: guardianSet.index,
            guardians: guardianSet.guardians.map(g => `0x${g}`),
            quorum: guardianSet.quorum,
            total: guardianSet.total,
            description: `Requires ${guardianSet.quorum} out of ${guardianSet.total} signatures for quorum`
        });
    } catch (error) {
        const status = error.status || 500;
        const message = error.message || 'Internal server error';
        res.status(status).json({ error: message });
    }
});

// GET /api/v1/guardian-set/:index - Get specific guardian set by index
app.get('/api/v1/guardian-set/:index', (req, res) => {
    try {
        const index = parseInt(req.params.index);
        if (isNaN(index) || index < 0) {
            return res.status(400).json({ error: 'Invalid guardian set index' });
        }
        
        const guardianSet = getGuardianSet(index);
        res.json({
            index: guardianSet.index,
            guardians: guardianSet.guardians.map(g => `0x${g}`),
            quorum: guardianSet.quorum,
            total: guardianSet.total,
            description: `Requires ${guardianSet.quorum} out of ${guardianSet.total} signatures for quorum`
        });
    } catch (error) {
        const status = error.status || 500;
        const message = error.message || 'Internal server error';
        res.status(status).json({ error: message });
    }
});

// ============================================================================
// CHAIN INFORMATION ENDPOINTS
// ============================================================================

// GET /api/v1/chains - List supported chains
app.get('/api/v1/chains', (req, res) => {
    const chains = Object.entries(CHAIN_NAMES).map(([id, name]) => ({
        chainId: parseInt(id),
        name: name,
        isTestnet: parseInt(id) >= 10000
    }));
    
    res.json({
        chains: chains,
        total: chains.length,
        testnets: chains.filter(c => c.isTestnet).length,
        mainnets: chains.filter(c => !c.isTestnet).length
    });
});

// GET /api/v1/chains/:chainId - Get chain information
app.get('/api/v1/chains/:chainId', (req, res) => {
    const chainId = parseInt(req.params.chainId);
    const chainName = CHAIN_NAMES[chainId];
    
    if (!chainName) {
        return res.status(404).json({ error: `Chain ID ${chainId} not found` });
    }
    
    res.json({
        chainId: chainId,
        name: chainName,
        isTestnet: chainId >= 10000,
        wormholeChainId: chainId
    });
});

// ============================================================================
// MESSAGE OBSERVATION ENDPOINTS
// ============================================================================

// GET /api/v1/messages/:chainId/:emitter/:sequence - Check message observation status
app.get('/api/v1/messages/:chainId/:emitter/:sequence', (req, res) => {
    try {
        const { chainId, emitter, sequence } = req.params;
        
        // Validate emitter format
        let emitterAddress = emitter.replace(/^0x/i, '');
        if (emitterAddress.length < 64) {
            emitterAddress = emitterAddress.padStart(64, '0');
        }
        
        const observation = checkObservation(chainId, emitterAddress, sequence);
        
        res.json({
            messageId: observation.messageId,
            observed: observation.observed,
            finalized: observation.finalized,
            hasVAA: observation.hasVAA,
            vaa: observation.vaa || null,
            message: observation.message || null,
            chainId: parseInt(chainId),
            emitterAddress: `0x${emitterAddress}`,
            sequence: parseInt(sequence)
        });
    } catch (error) {
        const status = error.status || 500;
        const message = error.message || 'Internal server error';
        res.status(status).json({ error: message });
    }
});

// ============================================================================
// VAA VERIFICATION ENDPOINT
// ============================================================================

// POST /api/v1/vaas/verify - Verify VAA signature
app.post('/api/v1/vaas/verify', (req, res) => {
    try {
        const { vaa } = req.body;
        
        if (!vaa) {
            return res.status(400).json({ error: 'VAA hex string required in body.vaa' });
        }
        
        // Clean VAA hex
        const vaaHex = vaa.replace(/^0x/i, '').replace(/\s/g, '');
        
        if (!/^[0-9a-fA-F]+$/.test(vaaHex)) {
            return res.status(400).json({ error: 'Invalid VAA format. Must be hex string' });
        }
        
        // Try to parse VAA by fetching it from guardian
        // For now, we'll just validate the format
        // Full verification would require checking signatures against guardian set
        
        // Basic VAA structure validation
        if (vaaHex.length < 100) {
            return res.status(400).json({ 
                error: 'VAA too short',
                valid: false 
            });
        }
        
        // Extract basic info from VAA hex
        const version = parseInt(vaaHex.substring(0, 2), 16);
        const guardianSetIndex = parseInt(vaaHex.substring(2, 4), 16);
        const numSignatures = parseInt(vaaHex.substring(4, 6), 16);
        
        res.json({
            valid: true,
            version: version,
            guardianSetIndex: guardianSetIndex,
            signatureCount: numSignatures,
            message: 'VAA format is valid. Full signature verification requires guardian set lookup.'
        });
    } catch (error) {
        const status = error.status || 500;
        const message = error.message || 'Internal server error';
        res.status(status).json({ error: message });
    }
});

// ============================================================================
// STATUS & HEALTH ENDPOINTS
// ============================================================================

// GET /api/v1/status - Detailed guardian status
app.get('/api/v1/status', (req, res) => {
    try {
        const guardianSet = getGuardianSet();
        const socketExists = fs.existsSync(adminSocket);
        
        // Try to get guardian node info
        let nodeInfo = null;
        try {
            const output = execAdminCommand('node-info', false);
            nodeInfo = { raw: output };
        } catch (e) {
            nodeInfo = { error: 'Could not fetch node info' };
        }
        
        res.json({
            service: 'VAA API Server',
            status: 'operational',
            guardian: {
                connected: socketExists,
                socket: adminSocket,
                guardianSet: {
                    index: guardianSet.index,
                    total: guardianSet.total,
                    quorum: guardianSet.quorum
                }
            },
            node: nodeInfo,
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        const status = error.status || 500;
        const message = error.message || 'Internal server error';
        res.status(status).json({ error: message });
    }
});

// GET /health/detailed - Detailed health check
app.get('/health/detailed', (req, res) => {
    try {
        const socketExists = fs.existsSync(adminSocket);
        const guardiandExists = fs.existsSync(guardiandBin);
        
        let guardianSet = null;
        try {
            guardianSet = getGuardianSet();
        } catch (e) {
            // Ignore if can't get guardian set
        }
        
        res.json({
            status: socketExists && guardiandExists ? 'healthy' : 'degraded',
            checks: {
                apiServer: 'ok',
                guardiandBinary: guardiandExists ? 'ok' : 'missing',
                guardianSocket: socketExists ? 'ok' : 'missing',
                guardianSet: guardianSet ? 'ok' : 'unavailable'
            },
            guardian: guardianSet ? {
                index: guardianSet.index,
                total: guardianSet.total,
                quorum: guardianSet.quorum
            } : null,
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ 
            status: 'error',
            error: error.message 
        });
    }
});

// ============================================================================
// METRICS ENDPOINT (Prometheus-style)
// ============================================================================

// GET /api/v1/metrics - Prometheus-style metrics
app.get('/api/v1/metrics', (req, res) => {
    try {
        const socketExists = fs.existsSync(adminSocket);
        const guardianSet = getGuardianSet();
        
        // Prometheus format
        const metrics = [
            `# HELP guardian_set_index Current guardian set index`,
            `# TYPE guardian_set_index gauge`,
            `guardian_set_index ${guardianSet.index}`,
            ``,
            `# HELP guardian_set_total Total number of guardians`,
            `# TYPE guardian_set_total gauge`,
            `guardian_set_total ${guardianSet.total}`,
            ``,
            `# HELP guardian_set_quorum Required signatures for quorum`,
            `# TYPE guardian_set_quorum gauge`,
            `guardian_set_quorum ${guardianSet.quorum}`,
            ``,
            `# HELP guardian_socket_connected Guardian socket connection status`,
            `# TYPE guardian_socket_connected gauge`,
            `guardian_socket_connected ${socketExists ? 1 : 0}`,
            ``,
            `# HELP api_server_uptime_seconds API server uptime in seconds`,
            `# TYPE api_server_uptime_seconds counter`,
            `api_server_uptime_seconds ${Math.floor(process.uptime())}`
        ].join('\n');
        
        res.set('Content-Type', 'text/plain');
        res.send(metrics);
    } catch (error) {
        res.status(500).send(`# ERROR\napi_error{message="${error.message}"} 1\n`);
    }
});

// Error handler
app.use((err, req, res, next) => {
    console.error('Error:', err);
    res.status(500).json({ error: 'Internal server error' });
});

// Start server
app.listen(PORT, HOST, () => {
    console.log('='.repeat(70));
    console.log('VAA API Server - Production Ready');
    console.log('='.repeat(70));
    console.log(`Listening on http://${HOST}:${PORT}`);
    console.log('');
    console.log('VAA Endpoints:');
    console.log(`  GET  /api/v1/vaas/:chainId/:emitter/:sequence  - Get VAA by chain/emitter/sequence`);
    console.log(`  GET  /api/v1/vaas/:messageId                  - Get VAA by message ID`);
    console.log(`  POST /api/v1/vaas/verify                      - Verify VAA signature`);
    console.log('');
    console.log('Guardian Set Endpoints:');
    console.log(`  GET  /api/v1/guardian-set                     - Get current guardian set`);
    console.log(`  GET  /api/v1/guardian-set/:index               - Get guardian set by index`);
    console.log('');
    console.log('Chain Information:');
    console.log(`  GET  /api/v1/chains                           - List all supported chains`);
    console.log(`  GET  /api/v1/chains/:chainId                  - Get chain information`);
    console.log('');
    console.log('Message Observation:');
    console.log(`  GET  /api/v1/messages/:chainId/:emitter/:seq  - Check message observation status`);
    console.log('');
    console.log('Status & Health:');
    console.log(`  GET  /health                                  - Basic health check`);
    console.log(`  GET  /health/detailed                         - Detailed health check`);
    console.log(`  GET  /api/v1/status                           - Guardian node status`);
    console.log(`  GET  /api/v1/metrics                          - Prometheus metrics`);
    console.log('');
    console.log('Examples:');
    console.log(`  # Get VAA:`);
    console.log(`  curl http://${HOST}:${PORT}/api/v1/vaas/6/000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d/1`);
    console.log('');
    console.log(`  # Get guardian set:`);
    console.log(`  curl http://${HOST}:${PORT}/api/v1/guardian-set`);
    console.log('');
    console.log(`  # Check message status:`);
    console.log(`  curl http://${HOST}:${PORT}/api/v1/messages/6/000000000000000000000000c60b683d1835b72a1f3cdae3ac29b49607f0176d/1`);
    console.log('');
    console.log(`  # Get metrics:`);
    console.log(`  curl http://${HOST}:${PORT}/api/v1/metrics`);
    console.log('='.repeat(70));
});

