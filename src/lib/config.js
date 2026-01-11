/**
 * Configuration Loader
 * Loads and parses guardian.conf file
 * 
 * SINGLE SOURCE OF TRUTH: All Node.js modules read from this loader
 */

const fs = require('fs');
const path = require('path');

const ROOT_DIR = path.resolve(__dirname, '../..');
const CONFIG_FILE = process.env.CONFIG_FILE || path.join(ROOT_DIR, 'config', 'guardian.conf');

let configCache = null;

/**
 * Parse guardian.conf file
 * @returns {Object} Configuration object
 */
function loadConfig() {
    if (configCache) return configCache;
    
    if (!fs.existsSync(CONFIG_FILE)) {
        throw new Error(`Configuration file not found: ${CONFIG_FILE}`);
    }
    
    const content = fs.readFileSync(CONFIG_FILE, 'utf-8');
    const config = {};
    
    for (const line of content.split('\n')) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) continue;
        
        const match = trimmed.match(/^([A-Z_][A-Z0-9_]*)=["']?([^"']*)["']?$/);
        if (match) {
            config[match[1]] = match[2];
        }
    }
    
    configCache = config;
    return config;
}

/**
 * Clear config cache (useful for testing or reloading)
 */
function clearCache() {
    configCache = null;
}

/**
 * Get a configuration value
 * @param {string} key - Configuration key
 * @param {string} defaultValue - Default value if key not found
 * @returns {string} Configuration value
 */
function get(key, defaultValue = '') {
    const config = loadConfig();
    return config[key] || defaultValue;
}

/**
 * Get all guardian addresses from config
 * @returns {string[]} Array of guardian addresses
 */
function getGuardianAddresses() {
    const config = loadConfig();
    
    // First check for comma-separated GUARDIAN_ADDRESSES
    if (config.GUARDIAN_ADDRESSES) {
        return config.GUARDIAN_ADDRESSES.split(',').map(a => a.trim());
    }
    
    // Fallback to individual GUARDIAN_X_ADDRESS entries
    const addresses = [];
    for (let i = 0; i < 19; i++) {
        const addr = config[`GUARDIAN_${i}_ADDRESS`];
        if (addr) addresses.push(addr);
    }
    
    return addresses;
}

/**
 * Get guardian addresses for deployment (specific count)
 * @param {number} count - Number of guardians to get addresses for
 * @returns {string[]} Array of guardian addresses
 */
function getGuardianAddressesForCount(count) {
    const config = loadConfig();
    const addresses = [];
    
    for (let i = 0; i < count && i < 19; i++) {
        const addr = config[`GUARDIAN_${i}_ADDRESS`];
        if (addr) {
            addresses.push(addr);
        }
    }
    
    if (addresses.length < count) {
        throw new Error(`Only ${addresses.length} guardian addresses defined, but ${count} requested`);
    }
    
    return addresses;
}

/**
 * Get all 19 devnet guardian addresses
 * @returns {Object} Map of hostname to address
 */
function getAllDevnetGuardians() {
    const config = loadConfig();
    const guardians = {};
    
    for (let i = 0; i < 19; i++) {
        const addr = config[`GUARDIAN_${i}_ADDRESS`];
        if (addr) {
            guardians[`guardian-${i}`] = addr;
        }
    }
    
    return guardians;
}

/**
 * Expand shell-like variables in string
 * @param {string} str - String with ${VAR} patterns
 * @param {Object} vars - Variables to expand
 */
function expandVars(str, vars) {
    if (!str) return str;
    return str.replace(/\$\{([^}]+)\}/g, (match, key) => vars[key] || match);
}

/**
 * Get file paths (with variable expansion)
 */
function getPaths() {
    const config = loadConfig();
    const index = config.GUARDIAN_INDEX || '0';
    
    // Variables to expand in paths
    const vars = { GUARDIAN_INDEX: index };
    
    return {
        root: ROOT_DIR,
        config: CONFIG_FILE,
        adminSocket: path.join(ROOT_DIR, expandVars(config.ADMIN_SOCKET, vars) || `data/guardian-${index}.sock`),
        logFile: path.join(ROOT_DIR, expandVars(config.LOG_FILE, vars) || `logs/guardian-${index}.log`),
        dataDir: path.join(ROOT_DIR, expandVars(config.DATA_DIR, vars) || `data/guardian-${index}`),
        keyFile: path.join(ROOT_DIR, expandVars(config.KEY_FILE, vars) || `keys/guardian-${index}.key`),
        guardiand: process.env.GUARDIAND_BIN || path.join(ROOT_DIR, '..', 'WormHole-Official-GitHub-Repo', 'build', 'bin', 'guardiand'),
    };
}

/**
 * Get Anvil/Geth configuration
 */
function getAnvilConfig() {
    const config = loadConfig();
    const host = config.ANVIL_HOST || '127.0.0.1';
    const port = config.ANVIL_PORT || '8545';
    
    return {
        host,
        port: parseInt(port),
        chainId: parseInt(config.ANVIL_CHAIN_ID || '31337'),
        rpcHttp: config.GETH_RPC_HTTP || `http://${host}:${port}`,
        rpcWs: config.GETH_RPC || `ws://${host}:${port}`,
        contract: config.GETH_CONTRACT,
        privateKey: config.ANVIL_PRIVATE_KEY || 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
    };
}

/**
 * Get Avalanche configuration
 */
function getAvalancheConfig() {
    const config = loadConfig();
    
    return {
        rpcHttp: config.AVALANCHE_RPC_HTTP,
        rpcWs: config.AVALANCHE_RPC,
        chainId: parseInt(config.AVALANCHE_CHAIN_ID || '0'),
        contract: config.AVALANCHE_CONTRACT,
    };
}

/**
 * Get Solana configuration
 */
function getSolanaConfig() {
    const config = loadConfig();
    
    return {
        rpc: config.SOLANA_RPC || 'http://127.0.0.1:8899',
        ws: config.SOLANA_WS || 'ws://127.0.0.1:8900',
        contract: config.SOLANA_CONTRACT,
        keypair: config.SOLANA_KEYPAIR || '~/.config/solana/id.json',
    };
}

/**
 * Get API server configuration
 */
function getApiConfig() {
    const config = loadConfig();
    
    return {
        port: parseInt(config.API_PORT || '3000'),
        grpcPort: parseInt(config.GRPC_PORT || '7000'),
        statusPort: parseInt(config.STATUS_PORT || '6600'),
    };
}

/**
 * Get guardian network configuration
 */
function getNetworkConfig() {
    const config = loadConfig();
    
    return {
        networkId: config.NETWORK_ID || '/wormhole/private/mainnet/1',
        numGuardians: parseInt(config.NUM_GUARDIANS || '1'),
        unsafeDevMode: config.UNSAFE_DEV_MODE === 'true',
        testnetMode: config.TESTNET_MODE === 'true',
    };
}

module.exports = {
    loadConfig,
    clearCache,
    get,
    getGuardianAddresses,
    getGuardianAddressesForCount,
    getAllDevnetGuardians,
    getPaths,
    getAnvilConfig,
    getAvalancheConfig,
    getSolanaConfig,
    getApiConfig,
    getNetworkConfig,
    ROOT_DIR,
    CONFIG_FILE,
};

