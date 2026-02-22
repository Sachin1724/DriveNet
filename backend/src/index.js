import express from 'express';
import { createServer } from 'http';
import cors from 'cors';
import dotenv from 'dotenv';
import authRoutes from './routes/auth.js';
import tunnelRoutes from './routes/tunnel.js';
import { tunnelBroker } from './tunnel/broker.js';

dotenv.config();

const app = express();
const server = createServer(app);

app.use(cors());

// Normalize double-slashes in URLs caused by bad frontend environment configs (e.g. `https://render.com//api/...` -> `.../api/...`)
app.use((req, res, next) => {
    if (req.url.includes('//')) {
        req.url = req.url.replace(/\/+/g, '/');
    }
    next();
});
app.use(express.json({ limit: '50gb' }));
app.use(express.urlencoded({ limit: '50gb', extended: true }));

// Main App Routes
app.use('/api/auth', authRoutes);
app.use('/api/fs', tunnelRoutes);

// Initialize WebSocket Tunnel Broker
tunnelBroker.init(server);

const PORT = process.env.PORT || 8000;
server.listen(PORT, () => {
    console.log(`[DriveNet Cloud] Server active on port ${PORT}`);
});
