/**
 * Status Routes
 * GET /api/v1/status
 */

const express = require('express');
const router = express.Router();
const fs = require('fs');
const config = require('../../lib/config');
const guardiand = require('../../lib/guardiand');

/**
 * GET /api/v1/status
 * Guardian node status
 */
router.get('/', (req, res) => {
    try {
        const paths = config.getPaths();
        const cfg = config.loadConfig();
        const guardians = config.getGuardianAddresses();
        
        const numGuardians = parseInt(cfg.NUM_GUARDIANS || guardians.length);
        const quorum = Math.floor((2 * numGuardians) / 3) + 1;
        
        res.json({
            service: 'Private Guardian Network',
            status: guardiand.isRunning() ? 'operational' : 'guardian_offline',
            guardian: {
                index: cfg.GUARDIAN_INDEX,
                connected: fs.existsSync(paths.adminSocket),
                networkId: cfg.NETWORK_ID,
            },
            guardianSet: {
                total: numGuardians,
                quorum,
                addresses: guardians,
            },
            chains: {
                ethereum: cfg.GETH_RPC ? 'configured' : 'not_configured',
                avalanche: cfg.AVALANCHE_RPC ? 'configured' : 'not_configured',
                solana: cfg.SOLANA_RPC ? 'configured' : 'not_configured',
            },
            timestamp: new Date().toISOString(),
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;

