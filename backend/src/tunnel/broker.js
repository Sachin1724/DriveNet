import { WebSocketServer } from 'ws';
import crypto from 'crypto';
import jwt from 'jsonwebtoken';

class TunnelBroker {
    constructor() {
        this.agents = new Map();       // agentId → WebSocket (live connections)
        this.pendingRequests = new Map(); // requestId → pending HTTP response
        // Persists drive info per user even after disconnect — email is the primary key
        this.agentInfo = new Map();    // agentId → { email, drive, online, lastSeen }
    }

    // Called by /api/me/agent route — returns drive info for the logged-in user
    getAgentInfo(agentId) {
        return this.agentInfo.get(agentId) || null;
    }

    init(server) {
        this.wss = new WebSocketServer({
            server,
            maxPayload: 1024 * 1024 * 1024 * 5 // 5GB limit for websocket payloads
        });

        this.wss.on('connection', (ws, req) => {
            const authHeader = req.headers['authorization'];
            const token = authHeader && authHeader.split(' ')[1];

            if (!token) {
                console.error(`[DriveNet] Agent connection rejected (No token): ${agentId}`);
                ws.close(1008, 'Token missing');
                return;
            }

            let decoded;
            try {
                decoded = jwt.verify(token, process.env.JWT_SECRET);
            } catch (err) {
                console.error(`[DriveNet] Agent connection rejected (Invalid token)`);
                ws.close(1008, 'Invalid token');
                return;
            }

            // SECURITY: Enforce Agent ID to the Google UID of the logged-in user
            const agentId = decoded.g_uid || decoded.user;

            if (!agentId) {
                console.error(`[DriveNet] Agent connection rejected (No Identity in Token)`);
                ws.close(1008, 'Identity Error');
                return;
            }

            console.log(`[DriveNet] Agent Connected & Authenticated for User: ${decoded.user} (AgentID: ${agentId})`);

            this.agents.set(agentId, ws);

            // Track this agent's email and online status — email is the primary key
            const existing = this.agentInfo.get(agentId) || {};
            this.agentInfo.set(agentId, {
                ...existing,
                email: decoded.user,
                agentId,
                online: true,
                lastSeen: new Date().toISOString(),
            });

            ws.on('message', (message) => {
                let data;
                try {
                    data = JSON.parse(message.toString());
                } catch (err) {
                    // Ignore non-JSON messages (e.g., ping frames)
                    return;
                }
                try {
                    if (data.requestId && this.pendingRequests.has(data.requestId)) {
                        const pendingReq = this.pendingRequests.get(data.requestId);

                        if (pendingReq.res) {
                            const res = pendingReq.res;
                            if (data.error) {
                                if (!res.headersSent) res.status(500).json({ error: data.error });
                                this.pendingRequests.delete(data.requestId);
                            } else if (data.payload && data.payload.type === 'start') {
                                if (data.payload.statusCode) {
                                    res.status(data.payload.statusCode);
                                }
                                if (data.payload.headers) {
                                    Object.entries(data.payload.headers).forEach(([key, value]) => {
                                        res.setHeader(key, value);
                                    });
                                } else {
                                    res.setHeader('Content-Disposition', `attachment; filename="${data.payload.filename || 'download.bin'}"`);
                                    if (data.payload.size !== undefined) {
                                        res.setHeader('Content-Length', data.payload.size);
                                    }
                                    res.setHeader('Content-Type', 'application/octet-stream');
                                }
                            } else if (data.payload && data.payload.type === 'chunk') {
                                res.write(Buffer.from(data.payload.data, 'base64'));
                            } else if (data.payload && data.payload.type === 'end') {
                                res.end();
                                this.pendingRequests.delete(data.requestId);
                            } else if (data.isFile) {
                                // Backward compatibility
                                const fileBuffer = Buffer.from(data.payload, 'base64');
                                res.setHeader('Content-Disposition', `attachment; filename="${data.filename || 'download.bin'}"`);
                                res.setHeader('Content-Type', 'application/octet-stream');
                                res.send(fileBuffer);
                                this.pendingRequests.delete(data.requestId);
                            } else {
                                res.json(data.payload);
                                this.pendingRequests.delete(data.requestId);
                            }
                        } else if (pendingReq.resolve) {
                            if (data.error) pendingReq.reject(new Error(data.error));
                            else pendingReq.resolve(data.payload);
                            this.pendingRequests.delete(data.requestId);
                        }
                    }
                } catch (err) {
                    console.error('WS MSG Handler Error:', err.message);
                }
            });

            ws.on('close', () => {
                console.log(`[DriveNet] Agent Disconnected: ${agentId}`);
                this.agents.delete(agentId);
                // Mark offline but keep the drive record so web can show last known drive
                const info = this.agentInfo.get(agentId);
                if (info) this.agentInfo.set(agentId, { ...info, online: false, lastSeen: new Date().toISOString() });
            });
        });
    }

    // Forward an HTTP request to the connected Agent via WebSocket
    async forwardRequest(agentId, action, payload = {}) {
        return new Promise((resolve, reject) => {
            const ws = this.agents.get(agentId);
            if (!ws || ws.readyState !== 1) {
                return reject(new Error('Agent is offline'));
            }

            const requestId = crypto.randomUUID();
            this.pendingRequests.set(requestId, { resolve, reject, timestamp: Date.now() });

            ws.send(JSON.stringify({
                requestId,
                action,
                payload
            }));

            // Timeout after 30 seconds
            setTimeout(() => {
                if (this.pendingRequests.has(requestId)) {
                    const req = this.pendingRequests.get(requestId);
                    req.reject(new Error('Agent response timeout'));
                    this.pendingRequests.delete(requestId);
                }
            }, 30000);
        });
    }

    // Specifically for HTTP routes
    createProxyHandler(action) {
        return async (req, res) => {
            try {
                // SECURITY: Route exactly to the agent associated with the requesting user
                const agentId = req.user?.g_uid || req.user?.user;
                if (!agentId) return res.status(401).json({ error: 'Unidentified User Request' });
                const requestId = crypto.randomUUID();

                const ws = this.agents.get(agentId);
                if (!ws || ws.readyState !== 1) {
                    return res.status(503).json({ error: 'SYSTEM OFFLINE. USB Agent disconnected.' });
                }

                this.pendingRequests.set(requestId, { res, timestamp: Date.now() });

                ws.send(JSON.stringify({
                    requestId,
                    action,
                    payload: { ...req.body, ...req.query, ...req.params, headers: req.headers }
                }));

                // Timeout after 30 seconds
                setTimeout(() => {
                    if (this.pendingRequests.has(requestId)) {
                        const pendingReq = this.pendingRequests.get(requestId);
                        if (!pendingReq.res.headersSent) {
                            pendingReq.res.status(504).json({ error: 'Agent response timeout' });
                        }
                        this.pendingRequests.delete(requestId);
                    }
                }, 30000);
            } catch (err) {
                console.error('Proxy Handler Error:', err);
                if (!res.headersSent) {
                    res.status(500).json({ error: 'Internal Server Error forwarding request.' });
                }
            }
        };
    }
}

export const tunnelBroker = new TunnelBroker();
