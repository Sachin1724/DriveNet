import express from 'express';
import { authenticateToken } from './auth.js';
import { tunnelBroker } from '../tunnel/broker.js';

const router = express.Router();

// Secure all file system routes
router.use(authenticateToken);

// Proxy these HTTP requests down the WebSocket tunnel to the Desktop Agent
router.get('/list', tunnelBroker.createProxyHandler('fs:list'));
router.post('/folder', tunnelBroker.createProxyHandler('fs:mkdir'));
router.delete('/delete', tunnelBroker.createProxyHandler('fs:delete'));
router.get('/stats', tunnelBroker.createProxyHandler('sys:stats'));

router.get('/download', tunnelBroker.createProxyHandler('fs:download'));
router.get('/thumbnail', tunnelBroker.createProxyHandler('fs:thumbnail'));

router.post('/upload_chunk', express.json({ limit: '10mb' }), tunnelBroker.createProxyHandler('fs:upload_chunk'));

// Use express.json to handle large base64 file payloads
router.post('/upload', express.json({ limit: '500mb' }), async (req, res) => {
    try {
        const { path: folderPath, name, content } = req.body;
        const agentId = req.user?.g_uid || req.user?.user;
        if (!agentId) return res.status(401).json({ error: 'Unidentified User Request' });
        const result = await tunnelBroker.forwardRequest(agentId, 'fs:upload', { path: folderPath, name, content });
        res.json(result);
    } catch (err) {
        res.status(500).json({ error: err.message || 'Tunnel Communication Error' });
    }
});

export default router;
