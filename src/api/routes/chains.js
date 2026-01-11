/**
 * Chain Information Routes
 * GET /api/v1/chains
 * GET /api/v1/chains/:chainId
 */

const express = require('express');
const router = express.Router();

// Wormhole chain definitions
const CHAINS = [
    { chainId: 1, name: 'Solana', type: 'solana' },
    { chainId: 2, name: 'Ethereum', type: 'evm' },
    { chainId: 3, name: 'Terra', type: 'cosmwasm' },
    { chainId: 4, name: 'BSC', type: 'evm' },
    { chainId: 5, name: 'Polygon', type: 'evm' },
    { chainId: 6, name: 'Avalanche', type: 'evm' },
    { chainId: 7, name: 'Oasis', type: 'evm' },
    { chainId: 8, name: 'Algorand', type: 'algorand' },
    { chainId: 9, name: 'Aurora', type: 'evm' },
    { chainId: 10, name: 'Fantom', type: 'evm' },
    { chainId: 11, name: 'Karura', type: 'evm' },
    { chainId: 12, name: 'Acala', type: 'evm' },
    { chainId: 13, name: 'Klaytn', type: 'evm' },
    { chainId: 14, name: 'Celo', type: 'evm' },
    { chainId: 15, name: 'NEAR', type: 'near' },
    { chainId: 16, name: 'Moonbeam', type: 'evm' },
    { chainId: 18, name: 'Terra2', type: 'cosmwasm' },
    { chainId: 19, name: 'Injective', type: 'cosmwasm' },
    { chainId: 21, name: 'Sui', type: 'sui' },
    { chainId: 22, name: 'Aptos', type: 'aptos' },
    { chainId: 23, name: 'Arbitrum', type: 'evm' },
    { chainId: 24, name: 'Optimism', type: 'evm' },
    { chainId: 30, name: 'Base', type: 'evm' },
];

/**
 * GET /api/v1/chains
 * List all supported chains
 */
router.get('/', (req, res) => {
    res.json(CHAINS);
});

/**
 * GET /api/v1/chains/:chainId
 * Get chain information
 */
router.get('/:chainId', (req, res) => {
    const { chainId } = req.params;
    const chain = CHAINS.find(c => c.chainId === parseInt(chainId));
    
    if (chain) {
        res.json(chain);
    } else {
        res.status(404).json({ error: 'Chain not found' });
    }
});

module.exports = router;

