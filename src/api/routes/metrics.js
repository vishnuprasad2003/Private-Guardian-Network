/**
 * Prometheus Metrics Routes
 * GET /api/v1/metrics
 */

const express = require('express');
const router = express.Router();
const fs = require('fs');
const config = require('../../lib/config');

/**
 * GET /api/v1/metrics
 * Prometheus format metrics
 */
router.get('/', (req, res) => {
    try {
        const paths = config.getPaths();
        const cfg = config.loadConfig();
        const guardians = config.getGuardianAddresses();
        
        const numGuardians = parseInt(cfg.NUM_GUARDIANS || guardians.length);
        const quorum = Math.floor((2 * numGuardians) / 3) + 1;
        
        let metrics = '';
        
        // Guardian set metrics
        metrics += '# HELP guardian_set_index Current guardian set index\n';
        metrics += '# TYPE guardian_set_index gauge\n';
        metrics += `guardian_set_index 0\n`;
        
        metrics += '# HELP guardian_set_total Total guardians in set\n';
        metrics += '# TYPE guardian_set_total gauge\n';
        metrics += `guardian_set_total ${numGuardians}\n`;
        
        metrics += '# HELP guardian_set_quorum Required signatures for quorum\n';
        metrics += '# TYPE guardian_set_quorum gauge\n';
        metrics += `guardian_set_quorum ${quorum}\n`;
        
        // Connection metrics
        metrics += '# HELP guardian_socket_connected Guardian socket connection status\n';
        metrics += '# TYPE guardian_socket_connected gauge\n';
        metrics += `guardian_socket_connected ${fs.existsSync(paths.adminSocket) ? 1 : 0}\n`;
        
        // API metrics
        metrics += '# HELP api_up API server up status\n';
        metrics += '# TYPE api_up gauge\n';
        metrics += `api_up 1\n`;
        
        res.set('Content-Type', 'text/plain');
        res.send(metrics);
        
    } catch (error) {
        res.status(500).send(`# ERROR: ${error.message}\n`);
    }
});

module.exports = router;

