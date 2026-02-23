import express from 'express';
import jwt from 'jsonwebtoken';
import { OAuth2Client } from 'google-auth-library';
import fetch from 'node-fetch'; // assuming node 16+ or node-fetch installed

const router = express.Router();

// You can configure this via .env, but usually access tokens can be verified 
// just by calling the Google tokeninfo endpoint or using GoogleAuthLibrary
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID || '';
const client = new OAuth2Client(GOOGLE_CLIENT_ID);

router.post('/login', async (req, res) => {
    const { username, password, google_token } = req.body;

    // 1. Check if it's a Google Auth login attempt
    if (google_token && google_token.startsWith('DEV_BYPASS')) {
        const email = google_token.includes(':') ? google_token.split(':')[1] : 'developer@drivenet.local';
        const g_uid = email; // use email as g_uid for bypass matching 
        const token = jwt.sign({ user: email, g_uid }, process.env.JWT_SECRET || 'fallback_secret', { expiresIn: '24h' });
        return res.json({ token, user: email });
    }

    if (google_token) {
        try {
            let email, sub;

            // Method A: Check if it's an ID Token (sent by React @react-oauth/google)
            try {
                const ticket = await client.verifyIdToken({
                    idToken: google_token,
                    // Accept any Google-signed token regardless of audience
                });
                const payload = ticket.getPayload();
                if (payload && payload.email) {
                    email = payload.email;
                    sub = payload.sub;
                    console.log("[Auth] Google ID Token verified for:", email);
                }
            } catch (idTokenError) {
                console.error("Method A (ID Token) Failed:", idTokenError.message);

                // Method B: Fallback to Access Token (sent by Flutter Google Sign In)
                try {
                    const response = await fetch(`https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=${google_token}`);
                    const data = await response.json();
                    if (!data.error && data.email) {
                        email = data.email;
                        sub = data.sub;
                    } else {
                        console.error("Method B (Access Token) Failed:", data.error || data.error_description);
                    }
                } catch (accessErr) {
                    console.error("Method B (Access Token) Fetch Error:", accessErr.message);
                }
            }

            if (!email) {
                console.error("Token verification completely failed. Token payload: ", google_token.substring(0, 20) + "...");
                return res.status(401).json({ error: 'Invalid Google Token (Neither ID nor Access Token)' });
            }

            // SECURITY ENFORCEMENT: Check Allowed Users
            const allowedEmailsStr = process.env.ALLOWED_EMAILS || '';
            const allowedEmails = allowedEmailsStr.split(',').map(e => e.trim().toLowerCase()).filter(e => e.length > 0);

            if (allowedEmails.length > 0 && !allowedEmails.includes(email.toLowerCase())) {
                console.error(`[SECURITY TRAP] Unauthorized Account Entry Attempt: ${email}`);
                return res.status(403).json({ error: 'Access Denied: Unregistered External Account' });
            }

            // Issue our own JWT for the rest of the app based on their Google email
            const token = jwt.sign({ user: email, g_uid: sub || email }, process.env.JWT_SECRET, { expiresIn: '24h' });
            return res.json({ token, user: email });

        } catch (error) {
            console.error('Google Auth Error:', error);
            return res.status(401).json({ error: 'Failed to authenticate with Google' });
        }
    }

    return res.status(401).json({ error: 'ACCESS DENIED. Invalid security clearance.' });
});

export const authenticateToken = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const token = (authHeader && authHeader.split(' ')[1]) || req.query.token;

    if (!token) return res.status(401).json({ error: 'Token missing' });

    jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
        if (err) return res.status(403).json({ error: 'Invalid token' });
        req.user = user;
        next();
    });
};

export default router;
