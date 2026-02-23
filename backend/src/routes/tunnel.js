import express from 'express';
import { authenticateToken } from './auth.js';
import { tunnelBroker } from '../tunnel/broker.js';

const router = express.Router();

// Secure all file system routes
router.use(authenticateToken);

// ─── DRIVE IDENTITY ROUTES ───────────────────────────────────────────────────

// GET /api/me/agent — Returns the drive assigned to the logged-in Gmail account + online status
// This is the key endpoint: email = primary key → drive + status
router.get('/me/agent', (req, res) => {
    const agentId = req.user?.g_uid || req.user?.user;
    if (!agentId) return res.status(401).json({ error: 'Unidentified User' });
    const info = tunnelBroker.getAgentInfo(agentId);
    if (!info) {
        return res.json({ online: false, drive: null, email: req.user?.user, message: 'No Windows agent has ever connected for this account.' });
    }
    return res.json(info);
});

// POST /api/me/register-drive — Windows agent calls this when going online to register its drive letter
// Body: { drive: "D:\\" }
router.post('/me/register-drive', express.json(), (req, res) => {
    const agentId = req.user?.g_uid || req.user?.user;
    if (!agentId) return res.status(401).json({ error: 'Unidentified User' });
    const { drive } = req.body;
    if (!drive) return res.status(400).json({ error: 'drive field required' });
    const existing = tunnelBroker.agentInfo.get(agentId) || {};
    tunnelBroker.agentInfo.set(agentId, {
        ...existing,
        email: req.user?.user,
        agentId,
        drive,
        online: tunnelBroker.agents.has(agentId),
        lastSeen: new Date().toISOString(),
    });
    console.log(`[DriveNet] Drive registered: ${req.user?.user} → ${drive}`);
    return res.json({ ok: true, drive, online: tunnelBroker.agents.has(agentId) });
});

// ─── FILE SYSTEM PROXY ROUTES (forwarded through WebSocket tunnel) ────────────

// Proxy these HTTP requests down the WebSocket tunnel to the Desktop Agent
router.get('/list', tunnelBroker.createProxyHandler('fs:list'));
router.post('/folder', tunnelBroker.createProxyHandler('fs:mkdir'));
router.delete('/delete', tunnelBroker.createProxyHandler('fs:delete'));
router.get('/stats', tunnelBroker.createProxyHandler('sys:stats'));

router.get('/download', tunnelBroker.createProxyHandler('fs:download'));
router.get('/video', tunnelBroker.createProxyHandler('fs:stream'));
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
