// Cloud Backend URL — works from ANY network worldwide
// The Windows agent connects here via WebSocket; the web/mobile connects here via HTTPS
// Both sides are bridged together by the cloud broker using your Google identity.
export const API = 'https://drivenet-broker.onrender.com';

// Google OAuth Client ID — this is the identity anchor (your Gmail is the key)
export const GOOGLE_CLIENT_ID = '319119253457-3tpsckf0g5ib959tuf0vdf4chp2kthic.apps.googleusercontent.com';
export const GOOGLE_ANDROID_CLIENT_ID = '901086875987-nekpj2rk5i3ep4shve7m6nou73qs1gfb.apps.googleusercontent.com';
