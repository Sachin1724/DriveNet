<div align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Node.js-43853D?style=for-the-badge&logo=node.js&logoColor=white" alt="Node.js" />
  <img src="https://img.shields.io/badge/React-20232A?style=for-the-badge&logo=react&logoColor=61DAFB" alt="React" />
  <img src="https://img.shields.io/badge/TypeScript-007ACC?style=for-the-badge&logo=typescript&logoColor=white" alt="TypeScript" />
  
  <br />
  <br />

  <h1>🚀 DriveNet</h1>
  <p><b>A highly-secure, multi-tenant cloud tunnel to access your personal Windows file system from anywhere in the world.</b></p>
  
  <h3>
    🌐 <a href="https://drive-78uot98tz-sachin1724s-projects.vercel.app">Access the Web Dashboard</a> &nbsp; | &nbsp; 
    💻 <a href="https://github.com/Sachin1724/DriveNet/raw/main/releases/DriveNet_Setup_v1.0.0.exe">Download Windows Agent Setup</a>
  </h3>
  <br />
</div>

---

## 📖 Overview

DriveNet completely bypasses the need for expensive cloud storage subscriptions (like Google Drive or Dropbox) by turning your own Windows Desktop PC into a private, high-speed cloud node. 

By running our incredibly lightweight **Native Flutter Windows Agent**, your hard drives are securely beamed via an encrypted WebSocket tunnel to the **DriveNet Cloud Proxy**, allowing you to seamlessly view, download, upload, and manage your entire file system from a beautiful **React Web Dashboard** on any device.

### ✨ Key Features
- **Zero-Trust Security:** Built-in Google OAuth2 (Google Sign-In). Multi-tenancy is enforced directly at the WebSocket router—you can only access systems logged into the exact same Google account.
- **Native Flutter Client:** The Windows desktop agent runs entirely in native Dart, utilizing Isolates for background image thumbnail crunching and stream manipulation without relying on clunky Electron or Node.js executables.
- **Infinite File Support:** Re-engineered with intelligent binary chunking streams. Capable of downloading or uploading 100GB+ files seamlessly over the WebSocket tunnel without memory exhaustion. 
- **Lightning Fast Grid View:** Image thumbnails are dynamically generated locally by the native Windows Agent and beamed to the browser to prevent UI lockup.

---

## 🏗️ Architecture

DriveNet is split into three distinct, decoupled modules:

1. **`windows_agent_ui/`**: A Native Flutter Windows application. It sits quietly in the system tray, scanning your `C:\` and `D:\` drives, answering requests, crunching filesystem data, and maintaining a constant connection to the Cloud Tunnel.
2. **`backend/`**: A lightweight Node.js Express server. This is the **Cloud Broker**. It intercepts HTTP commands from the website, verifies your Google JWT, and proxies the request via WebSocket directly down to your home computer.
3. **`frontend/`**: A beautiful React/Vite dashboard built with Tailwind CSS.

---

## ⚡ Quick Start (Running Locally)

### 1. The Cloud Broker (Backend)
The central nervous system of the tunnel.
```bash
cd backend
npm install
# Copy the `.env.example` to `.env` and fill in your Google Client ID and custom JWT Secret
npm start
```

### 2. The Web Dashboard (Frontend)
The user interface to view your files.
```bash
cd frontend
npm install
# Copy the `.env.example` to `.env` and fill in your Google Client ID
npm run dev
```

### 3. The Windows Agent 
The relay client installed on the host computer containing the files. 

**For developers:** You will need the [Flutter SDK for Windows](https://docs.flutter.dev/get-started/install/windows) installed. 
```bash
cd windows_agent_ui
flutter pub get
flutter run -d windows
```

> **Not a developer?** Just download the pre-compiled `DriveNet.exe` from the **Releases** tab on the right side of this GitHub page! No compilers required.

---

## 🌍 Deploying to Production

To take DriveNet out of `localhost` and into the real world for true global access:

1. **Host the Backend:** Deploy the `backend/` folder to a service like Render, Railway, or a cheap Ubuntu VPS. **Ensure you put it behind `https://` (SSL) using Nginx/Certbot**.
2. **Host the Frontend:** Run `npm run build` in the `frontend` folder and drag the `dist` folder into a static host like Vercel, Netlify, or Cloudflare Pages.
3. **Compile the Executable:** Run `flutter build windows --release` in the `windows_agent_ui` folder. Zip up the output directory and distribute it to your PCs!

> *Refer to the code comments and `deployment_guide.md` (if attached in your records) for advanced Multi-Tenant configurations.*

---

## 🤝 Contributing & License

Thank you so much to everyone interested in self-sovereign data solutions! DriveNet is fully open-source. Feel free to submit Pull Requests to expand into macOS/Linux agents, introduce background sync scheduling, or add more robust video streaming capabilities.

---
<div align="center">
  <i>If you found this useful, don't forget to ⭐ the repository!</i><br/>
  <b>Thank You!</b>
</div>
