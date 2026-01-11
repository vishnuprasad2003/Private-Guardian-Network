/**
 * Message Status Routes
 * GET /api/v1/messages/:chainId/:emitter/:sequence
 */

const express = require('express');
const router = express.Router();
const guardiand = require('../../lib/guardiand');

/**
 * Normalize emitter address
 */
function normalizeEmitter(emitter) {
    return emitter.replace(/^0x/i, '').toLowerCase().padStart(64, '0');
}

/**
 * GET /api/v1/messages/:chainId/:emitter/:sequence
 * Check message observation status
 */
router.get('/:chainId/:emitter/:sequence', (req, res) => {
    try {
        const { chainId, emitter, sequence } = req.params;
        const normalizedEmitter = normalizeEmitter(emitter);
        const messageId = `${chainId}/${normalizedEmitter}/${sequence}`;
        
        // Try to fetch VAA
        const result = guardiand.fetchVAA(chainId, normalizedEmitter, sequence);
        
        if (result && result.vaaHex) {
            res.json({
                messageId,
                observed: true,
                finalized: true,
                hasVAA: true,
                vaa: {
                    digest: result.digest,
                    timestamp: result.vaaJson?.Timestamp,
                },
                chainId: parseInt(chainId),
                emitterAddress: `0x${normalizedEmitter}`,
                sequence: parseInt(sequence),
            });
        } else {
            res.json({
                messageId,
                observed: false,
                finalized: false,
                hasVAA: false,
                message: 'VAA not yet observed',
                chainId: parseInt(chainId),
                emitterAddress: `0x${normalizedEmitter}`,
                sequence: parseInt(sequence),
            });
        }
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;

