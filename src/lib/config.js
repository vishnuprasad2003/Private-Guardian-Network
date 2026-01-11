/**
 * Configuration Loader
 * Loads and parses guardian.conf file
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
    const addresses = [];
    
    for (let i = 0; i < 19; i++) {
        const addr = config[`GUARDIAN_${i}_ADDRESS`];
        if (addr) addresses.push(addr);
    }
    
    return addresses;
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
 * Get paths
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

module.exports = {
    loadConfig,
    get,
    getGuardianAddresses,
    getPaths,
    ROOT_DIR,
    CONFIG_FILE,
};

