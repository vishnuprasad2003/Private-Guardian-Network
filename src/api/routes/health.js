/**
 * Health Check Routes
 * GET /health
 * GET /health/detailed
 */

const express = require('express');
const router = express.Router();
const fs = require('fs');
const config = require('../../lib/config');
const guardiand = require('../../lib/guardiand');

/**
 * GET /health
 * Basic health check
 */
router.get('/', (req, res) => {
    const paths = config.getPaths();
    
    res.json({
        status: 'ok',
        service: 'VAA API Server',
        guardian: {
            socket: paths.adminSocket,
            connected: fs.existsSync(paths.adminSocket),
        },
    });
});

/**
 * GET /health/detailed
 * Detailed health check
 */
router.get('/detailed', (req, res) => {
    try {
        const paths = config.getPaths();
        const cfg = config.loadConfig();
        
        const checks = {
            apiServer: 'ok',
            guardiandBinary: fs.existsSync(paths.guardiand) ? 'ok' : 'missing',
            guardianSocket: fs.existsSync(paths.adminSocket) ? 'ok' : 'disconnected',
            configFile: fs.existsSync(paths.config) ? 'ok' : 'missing',
        };
        
        const overallStatus = Object.values(checks).every(v => v === 'ok') 
            ? 'healthy' 
            : 'degraded';
        
        res.json({
            status: overallStatus,
            checks,
            config: {
                guardianIndex: cfg.GUARDIAN_INDEX,
                networkId: cfg.NETWORK_ID,
                numGuardians: cfg.NUM_GUARDIANS,
            },
            paths: {
                adminSocket: paths.adminSocket,
                dataDir: paths.dataDir,
                logFile: paths.logFile,
            },
            timestamp: new Date().toISOString(),
        });
        
    } catch (error) {
        res.status(500).json({ 
            status: 'error', 
            error: error.message 
        });
    }
});

module.exports = router;

