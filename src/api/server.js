#!/usr/bin/env node
/**
 * VAA API Server
 * REST API for fetching VAAs from the guardian network
 * 
 * Usage: node src/api/server.js
 * 
 * Environment:
 *   PORT - Server port (default: 3000)
 *   HOST - Server host (default: 0.0.0.0)
 */

const express = require('express');
const cors = require('cors');
const path = require('path');

// Routes
const vaaRoutes = require('./routes/vaa');
const guardianRoutes = require('./routes/guardian');
const healthRoutes = require('./routes/health');

const app = express();
app.use(express.json());
app.use(cors());

// Configuration
const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';

// Request logging
app.use((req, res, next) => {
    const timestamp = new Date().toISOString();
    console.log(`[${timestamp}] ${req.method} ${req.url}`);
    next();
});

// Routes
app.use('/health', healthRoutes);
app.use('/api/v1/vaas', vaaRoutes);
app.use('/api/v1/guardian-set', guardianRoutes);
app.use('/api/v1/chains', require('./routes/chains'));
app.use('/api/v1/messages', require('./routes/messages'));
app.use('/api/v1/status', require('./routes/status'));
app.use('/api/v1/metrics', require('./routes/metrics'));

// API documentation
app.get('/', (req, res) => {
    res.json({
        name: 'Private Guardian Network API',
        version: '1.0.0',
        endpoints: {
            health: 'GET /health',
            vaas: {
                get: 'GET /api/v1/vaas/:chainId/:emitter/:sequence',
                verify: 'POST /api/v1/vaas/verify',
            },
            guardianSet: {
                current: 'GET /api/v1/guardian-set',
                byIndex: 'GET /api/v1/guardian-set/:index',
            },
            chains: {
                list: 'GET /api/v1/chains',
                get: 'GET /api/v1/chains/:chainId',
            },
            messages: 'GET /api/v1/messages/:chainId/:emitter/:sequence',
            status: 'GET /api/v1/status',
            metrics: 'GET /api/v1/metrics',
        },
    });
});

// Error handler
app.use((err, req, res, next) => {
    console.error('Error:', err);
    res.status(500).json({ error: 'Internal server error' });
});

// Start server
app.listen(PORT, HOST, () => {
    console.log('='.repeat(60));
    console.log('Private Guardian Network - VAA API Server');
    console.log('='.repeat(60));
    console.log(`Listening: http://${HOST}:${PORT}`);
    console.log('');
    console.log('Endpoints:');
    console.log('  GET  /health                             Health check');
    console.log('  GET  /api/v1/vaas/:chain/:emitter/:seq   Get VAA');
    console.log('  POST /api/v1/vaas/verify                 Verify VAA');
    console.log('  GET  /api/v1/guardian-set                Get guardian set');
    console.log('  GET  /api/v1/chains                      List chains');
    console.log('  GET  /api/v1/messages/:chain/:em/:seq    Message status');
    console.log('  GET  /api/v1/status                      Node status');
    console.log('  GET  /api/v1/metrics                     Prometheus metrics');
    console.log('='.repeat(60));
});

