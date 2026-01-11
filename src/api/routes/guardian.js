/**
 * Guardian Set Routes
 * GET /api/v1/guardian-set
 * GET /api/v1/guardian-set/:index
 */

const express = require('express');
const router = express.Router();
const config = require('../../lib/config');

/**
 * GET /api/v1/guardian-set
 * Get current guardian set
 */
router.get('/', (req, res) => {
    try {
        const cfg = config.loadConfig();
        const guardians = config.getGuardianAddresses();
        const numGuardians = parseInt(cfg.NUM_GUARDIANS || guardians.length);
        const quorum = Math.floor((2 * numGuardians) / 3) + 1;
        
        res.json({
            index: 0,
            guardians,
            total: numGuardians,
            quorum,
            networkId: cfg.NETWORK_ID,
            description: `Requires ${quorum} of ${numGuardians} signatures`,
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

/**
 * GET /api/v1/guardian-set/:index
 * Get guardian set by index
 */
router.get('/:index', (req, res) => {
    try {
        const { index } = req.params;
        
        // Private network only has index 0
        if (parseInt(index) !== 0) {
            return res.status(404).json({ 
                error: 'Guardian set not found for this index' 
            });
        }
        
        // Return same as current
        const cfg = config.loadConfig();
        const guardians = config.getGuardianAddresses();
        const numGuardians = parseInt(cfg.NUM_GUARDIANS || guardians.length);
        const quorum = Math.floor((2 * numGuardians) / 3) + 1;
        
        res.json({
            index: 0,
            guardians,
            total: numGuardians,
            quorum,
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;

