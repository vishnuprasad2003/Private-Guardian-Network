/**
 * VAA Routes
 * GET /api/v1/vaas/:chainId/:emitter/:sequence
 * POST /api/v1/vaas/verify
 */

const express = require('express');
const router = express.Router();
const guardiand = require('../../lib/guardiand');

/**
 * Normalize emitter address to 32-byte hex
 */
function normalizeEmitter(emitter) {
    let addr = emitter.replace(/^0x/i, '').toLowerCase();
    return addr.padStart(64, '0');
}

/**
 * GET /api/v1/vaas/:chainId/:emitter/:sequence
 * Get VAA by chain, emitter, and sequence
 */
router.get('/:chainId/:emitter/:sequence', (req, res) => {
    try {
        const { chainId, emitter, sequence } = req.params;
        
        // Validate inputs
        if (!/^\d+$/.test(chainId)) {
            return res.status(400).json({ error: 'Invalid chainId' });
        }
        
        const normalizedEmitter = normalizeEmitter(emitter);
        if (!/^[0-9a-f]{64}$/.test(normalizedEmitter)) {
            return res.status(400).json({ error: 'Invalid emitter address' });
        }
        
        if (!/^\d+$/.test(sequence)) {
            return res.status(400).json({ error: 'Invalid sequence' });
        }
        
        // Fetch VAA
        const result = guardiand.fetchVAA(chainId, normalizedEmitter, sequence);
        
        if (!result || !result.vaaHex) {
            return res.status(404).json({
                error: 'VAA not found',
                messageId: `${chainId}/${normalizedEmitter}/${sequence}`,
            });
        }
        
        // Build response
        const response = {
            vaa: result.vaaHex,
            digest: result.digest,
            messageId: `${chainId}/${normalizedEmitter}/${sequence}`,
        };
        
        if (result.vaaJson) {
            response.parsed = {
                version: result.vaaJson.Version,
                guardianSetIndex: result.vaaJson.GuardianSetIndex,
                timestamp: result.vaaJson.Timestamp,
                nonce: result.vaaJson.Nonce,
                sequence: result.vaaJson.Sequence,
                consistencyLevel: result.vaaJson.ConsistencyLevel,
                emitterChain: result.vaaJson.EmitterChain,
                emitterAddress: result.vaaJson.EmitterAddress,
                payload: result.vaaJson.Payload,
                signatures: result.vaaJson.Signatures?.length || 0,
            };
            
            // Decode payload
            if (result.vaaJson.Payload) {
                try {
                    const payloadBuf = Buffer.from(result.vaaJson.Payload, 'base64');
                    response.parsed.payloadHex = payloadBuf.toString('hex');
                    const text = payloadBuf.toString('utf8');
                    if (/^[\x20-\x7E]+$/.test(text)) {
                        response.parsed.payloadText = text;
                    }
                } catch (e) {}
            }
        }
        
        res.json(response);
        
    } catch (error) {
        console.error('Error fetching VAA:', error.message);
        res.status(500).json({ error: error.message });
    }
});

/**
 * GET /api/v1/vaas/:messageId
 * Get VAA by message ID (chain/emitter/sequence)
 */
router.get('/:messageId(*)', (req, res) => {
    try {
        const parts = req.params.messageId.split('/');
        if (parts.length !== 3) {
            return res.status(400).json({ 
                error: 'Invalid message ID format. Use: chainId/emitter/sequence' 
            });
        }
        
        req.params.chainId = parts[0];
        req.params.emitter = parts[1];
        req.params.sequence = parts[2];
        
        // Forward to main handler
        return router.handle(req, res, () => {});
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

/**
 * POST /api/v1/vaas/verify
 * Verify VAA format
 */
router.post('/verify', (req, res) => {
    try {
        const { vaaHex } = req.body;
        
        if (!vaaHex) {
            return res.status(400).json({ error: 'Missing vaaHex in request body' });
        }
        
        const cleanHex = vaaHex.replace(/^0x/i, '');
        
        if (!/^[0-9a-fA-F]+$/.test(cleanHex)) {
            return res.status(400).json({ error: 'Invalid hex format' });
        }
        
        if (cleanHex.length < 200) {
            return res.status(400).json({ error: 'VAA too short' });
        }
        
        // Parse VAA header
        const version = parseInt(cleanHex.slice(0, 2), 16);
        const guardianSetIndex = parseInt(cleanHex.slice(2, 10), 16);
        const signatureCount = parseInt(cleanHex.slice(10, 12), 16);
        
        res.json({
            valid: true,
            version,
            guardianSetIndex,
            signatureCount,
            length: cleanHex.length / 2,
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;

