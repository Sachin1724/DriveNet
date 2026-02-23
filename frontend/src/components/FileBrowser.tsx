import React, { useEffect, useState, useCallback, useRef } from 'react';
import axios from 'axios';
import { useNavigate } from 'react-router-dom';

interface FileItem { name: string; is_dir: boolean; size: number; modified: number; }
interface SystemStats { cpu: number; ram: number; up: number; down: number; storageTotal: number; storageAvailable: number; }
interface ActivityEntry { name: string; action: string; time: number; size: number; }
type Tab = 'dashboard' | 'allfiles' | 'recent' | 'shared';
type ViewMode = 'list' | 'grid';

const RAW_API = import.meta.env.VITE_API_URL || 'http://localhost:8000';
const API = RAW_API.endsWith('/') ? RAW_API.slice(0, -1) : RAW_API;

// In-memory blob cache: path → objectURL (kept until page refresh)
const blobCache = new Map<string, string>();

function loadActivity(): ActivityEntry[] {
    try { return JSON.parse(sessionStorage.getItem('dn_activity') || '[]'); } catch { return []; }
}
function saveActivity(a: ActivityEntry[]) {
    try { sessionStorage.setItem('dn_activity', JSON.stringify(a.slice(0, 100))); } catch { }
}

const FileBrowser: React.FC = () => {
    const [activeTab, setActiveTab] = useState<Tab>('dashboard');
    const [currentPath, setCurrentPath] = useState('');
    const [files, setFiles] = useState<FileItem[]>([]);
    const [loading, setLoading] = useState(false);
    const [sysStats, setSysStats] = useState<SystemStats | null>(null);
    const [agentOnline, setAgentOnline] = useState(false);
    const [userEmail, setUserEmail] = useState('AGENT_ADMIN');
    const [uploadProgress, setUploadProgress] = useState<{ [k: string]: number }>({});
    const [activity, setActivity] = useState<ActivityEntry[]>(loadActivity);
    const [toast, setToast] = useState<{ msg: string; ok: boolean } | null>(null);
    const [viewMode, setViewMode] = useState<ViewMode>('list');
    const [filter, setFilter] = useState('');
    const [gridCache, setGridCache] = useState<{ [path: string]: string }>({}); // thumb URLs

    // Preview
    const [previewUrl, setPreviewUrl] = useState<string | null>(null);
    const [previewType, setPreviewType] = useState<'image' | 'pdf' | 'video' | 'text' | null>(null);
    const [previewText, setPreviewText] = useState<string>('');
    const [videoQuality, setVideoQuality] = useState<'original' | 'low'>('original');
    const [previewName, setPreviewName] = useState<string | null>(null);
    const [previewLoading, setPreviewLoading] = useState(false);

    const navigate = useNavigate();
    const pollRef = useRef<ReturnType<typeof setInterval> | undefined>(undefined);

    const showToast = (msg: string, ok: boolean) => {
        setToast({ msg, ok });
        setTimeout(() => setToast(null), 3500);
    };

    const authHeader = useCallback(() => {
        const token = localStorage.getItem('drivenet_token');
        return { Authorization: `Bearer ${token}` };
    }, []);

    const addActivity = useCallback((entry: ActivityEntry) => {
        setActivity(prev => {
            const next = [entry, ...prev.slice(0, 99)];
            saveActivity(next);
            return next;
        });
    }, []);

    const fetchFiles = useCallback(async (p: string, silent = false) => {
        if (!silent) setLoading(true);
        try {
            const res = await axios.get(`${API}/api/fs/list?path=${encodeURIComponent(p)}`, { headers: authHeader() });
            if (res.data?.items) {
                setFiles(res.data.items);
                setCurrentPath(res.data.path ?? p);
                setAgentOnline(true);
            }
        } catch {
            if (!silent) setAgentOnline(false);
        } finally {
            if (!silent) setLoading(false);
        }
    }, [authHeader]);

    const fetchStats = useCallback(async () => {
        try {
            const res = await axios.get(`${API}/api/fs/stats`, { headers: authHeader() });
            if (res.data && !res.data.error) { setSysStats(res.data); setAgentOnline(true); }
        } catch { setAgentOnline(false); }
    }, [authHeader]);

    // Real-time polling every 5s
    useEffect(() => {
        const token = localStorage.getItem('drivenet_token');
        if (token) {
            try {
                const p = JSON.parse(atob(token.split('.')[1]));
                setUserEmail(p.user ?? 'AGENT_ADMIN');
            } catch { }
        }
        fetchFiles('');
        fetchStats();

        pollRef.current = setInterval(() => {
            fetchFiles(currentPath, true); // silent = no loading spinner
            fetchStats();
        }, 5000);

        return () => clearInterval(pollRef.current);
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    // Restart poll whenever path changes
    useEffect(() => {
        clearInterval(pollRef.current);
        pollRef.current = setInterval(() => fetchFiles(currentPath, true), 5000);
        return () => clearInterval(pollRef.current);
    }, [currentPath, fetchFiles]);

    const formatBytes = (b: number) => {
        if (!b || b <= 0) return '0 B';
        const k = 1024, s = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(b) / Math.log(k));
        return parseFloat((b / Math.pow(k, i)).toFixed(1)) + ' ' + s[i];
    };

    const formatDate = (ts: number) => {
        if (!ts) return '—';
        const d = new Date(ts);
        return d.toLocaleDateString() + ' ' + d.toTimeString().slice(0, 8);
    };

    const getExt = (name: string) => name.split('.').pop()?.toLowerCase() ?? '';
    const isImage = (name: string) => ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg'].includes(getExt(name));
    const isVideo = (name: string) => ['mp4', 'webm', 'mov', 'avi', 'mkv'].includes(getExt(name));
    const isPDF = (name: string) => getExt(name) === 'pdf';
    const isText = (name: string) => ['txt', 'md', 'json', 'csv', 'js', 'ts', 'jsx', 'tsx', 'html', 'css', 'ini', 'yaml', 'yml'].includes(getExt(name));

    const fileIcon = (file: FileItem) => {
        if (file.is_dir) return 'folder';
        const e = getExt(file.name);
        const m: Record<string, string> = { jpg: 'image', jpeg: 'image', png: 'image', gif: 'image', webp: 'image', mp4: 'videocam', webm: 'videocam', mov: 'videocam', pdf: 'picture_as_pdf', zip: 'folder_zip', rar: 'folder_zip', mp3: 'music_note', wav: 'music_note', doc: 'description', docx: 'description', txt: 'description', xls: 'table_chart', xlsx: 'table_chart' };
        return m[e] ?? 'insert_drive_file';
    };

    // Load/cache a blob URL for a file path
    const getOrFetchBlob = async (rel: string): Promise<string | null> => {
        if (blobCache.has(rel)) return blobCache.get(rel)!;
        try {
            const res = await axios.get(`${API}/api/fs/download?path=${encodeURIComponent(rel)}`, {
                headers: authHeader(), responseType: 'blob'
            });
            const url = URL.createObjectURL(res.data);
            blobCache.set(rel, url);
            return url;
        } catch { return null; }
    };

    useEffect(() => {
        if (previewType === 'video' && previewName) {
            const rel = currentPath ? `${currentPath}/${previewName}` : previewName;
            const token = localStorage.getItem('drivenet_token') || '';
            setPreviewUrl(`${API}/api/fs/video?path=${encodeURIComponent(rel)}&token=${token}&quality=${videoQuality}`);
        }
    }, [videoQuality]);

    const handleFileClick = async (file: FileItem) => {
        if (file.is_dir) {
            const newPath = currentPath ? `${currentPath}/${file.name}` : file.name;
            fetchFiles(newPath);
            return;
        }
        const rel = currentPath ? `${currentPath}/${file.name}` : file.name;
        if (isImage(file.name) || isVideo(file.name) || isPDF(file.name) || isText(file.name)) {
            setPreviewLoading(true);
            setPreviewName(file.name);
            setPreviewUrl(null);
            setPreviewText('');

            const isVid = isVideo(file.name);
            const isTxt = isText(file.name);
            setPreviewType(isImage(file.name) ? 'image' : isVid ? 'video' : isPDF(file.name) ? 'pdf' : 'text');

            if (isVid) {
                const token = localStorage.getItem('drivenet_token') || '';
                setPreviewUrl(`${API}/api/fs/video?path=${encodeURIComponent(rel)}&token=${token}&quality=${videoQuality}`);
                setPreviewLoading(false);
            } else if (isTxt) {
                try {
                    const res = await axios.get(`${API}/api/fs/download?path=${encodeURIComponent(rel)}`, {
                        headers: authHeader(), responseType: 'text'
                    });
                    setPreviewText(res.data);
                } catch { setPreviewText('Error loading document content.'); }
                setPreviewLoading(false);
            } else {
                const url = await getOrFetchBlob(rel);
                setPreviewUrl(url);
                setPreviewLoading(false);
            }
        } else {
            // Download directly
            const url = await getOrFetchBlob(rel);
            if (url) {
                const a = document.createElement('a');
                a.href = url;
                a.download = file.name;
                a.click();
            }
        }
    };

    // Preload thumbnails for images in grid view
    const preloadGridThumbs = useCallback(async (items: FileItem[], path: string) => {
        const images = items.filter(f => !f.is_dir && isImage(f.name)).slice(0, 20);
        for (const img of images) {
            const rel = path ? `${path}/${img.name}` : img.name;
            if (!blobCache.has(rel)) {
                try {
                    const res = await axios.get(`${API}/api/fs/thumbnail?path=${encodeURIComponent(rel)}`, {
                        headers: authHeader(), responseType: 'blob'
                    });
                    const url = URL.createObjectURL(res.data);
                    blobCache.set(rel, url);
                    setGridCache(prev => ({ ...prev, [rel]: url }));
                } catch { }
            } else {
                setGridCache(prev => ({ ...prev, [rel]: blobCache.get(rel)! }));
            }
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [authHeader]);

    useEffect(() => {
        if (viewMode === 'grid' && files.length > 0) {
            preloadGridThumbs(files, currentPath);
        }
    }, [viewMode, files, currentPath, preloadGridThumbs]);

    const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (!file) return;

        setUploadProgress(p => ({ ...p, [file.name]: 0 }));
        const CHUNK_SIZE = 1 * 1024 * 1024; // 1MB
        const uploadId = window.crypto.randomUUID();

        try {
            // For zero-byte files
            if (file.size === 0) {
                await axios.post(`${API}/api/fs/upload_chunk`, {
                    uploadId, path: currentPath, name: file.name, chunk: '', isFirst: true, isLast: true
                }, { headers: authHeader() });
            } else {
                for (let i = 0; i < file.size; i += CHUNK_SIZE) {
                    const chunkBlob = file.slice(i, i + CHUNK_SIZE);
                    const isFirst = i === 0;
                    const isLast = (i + CHUNK_SIZE) >= file.size;

                    const base64 = await new Promise<string>((resolve) => {
                        const reader = new FileReader();
                        reader.onload = (ev) => resolve(ev.target?.result as string);
                        reader.readAsDataURL(chunkBlob);
                    });

                    await axios.post(`${API}/api/fs/upload_chunk`, {
                        uploadId, path: currentPath, name: file.name, chunk: base64, isFirst, isLast
                    }, { headers: authHeader() });

                    const pct = Math.min(100, Math.round(((i + CHUNK_SIZE) / file.size) * 100));
                    setUploadProgress(p => ({ ...p, [file.name]: pct }));
                }
            }

            setUploadProgress(p => { const n = { ...p }; delete n[file.name]; return n; });
            addActivity({ name: file.name, action: 'UPLOADED', time: Date.now(), size: file.size });
            showToast(`✓ ${file.name} uploaded`, true);
            fetchFiles(currentPath);
        } catch (err: any) {
            setUploadProgress(p => { const n = { ...p }; delete n[file.name]; return n; });
            showToast('Upload failed — agent disconnected or network error', false);
        }

        e.target.value = '';
    };

    const handleDelete = async (file: FileItem, e?: React.MouseEvent) => {
        if (e) e.stopPropagation();
        if (!file.name || !confirm(`Delete "${file.name}"?`)) return;
        const rel = currentPath ? `${currentPath}/${file.name}` : file.name;
        try {
            await axios.delete(`${API}/api/fs/delete?path=${encodeURIComponent(rel)}`, { headers: authHeader() });
            addActivity({ name: file.name, action: 'DELETED', time: Date.now(), size: file.size });
            showToast(`${file.name} deleted`, true);
            fetchFiles(currentPath);
        } catch { showToast('Delete failed', false); }
    };

    const navigateUp = () => {
        if (!currentPath) return;
        const parts = currentPath.split('/');
        parts.pop();
        fetchFiles(parts.join('/'));
    };

    const handleLogout = () => { localStorage.removeItem('drivenet_token'); navigate('/'); };

    const storageUsed = sysStats ? sysStats.storageTotal - sysStats.storageAvailable : 0;
    const storagePct = sysStats && sysStats.storageTotal > 0 ? (storageUsed / sysStats.storageTotal) * 100 : 0;

    const filteredFiles = files.filter(f => f.name.toLowerCase().includes(filter.toLowerCase()));

    const NavBtn = ({ tab, icon, label }: { tab: Tab; icon: string; label: string }) => (
        <button onClick={() => setActiveTab(tab)}
            className={`w-full p-3 flex items-center gap-3 font-bold text-xs uppercase tracking-widest transition-all text-left rounded-sm
        ${activeTab === tab ? 'bg-primary text-white shadow-[0_0_12px_rgba(255,70,85,0.3)]' : 'text-slate-400 hover:text-white hover:bg-white/5'}`}>
            <span className="material-symbols-outlined text-lg">{icon}</span>
            {label}
            {tab === 'recent' && activity.length > 0 && (
                <span className="ml-auto bg-primary/80 text-white text-[8px] font-bold px-1.5 py-0.5 rounded">{activity.length}</span>
            )}
        </button>
    );

    const FileListRow = ({ file }: { file: FileItem }) => (
        <tr className="border-b border-[#1a1a1a] hover:bg-white/[0.025] group transition-colors cursor-pointer" onClick={() => handleFileClick(file)}>
            <td className="py-3 px-4">
                <div className="flex items-center gap-3">
                    <span className={`material-symbols-outlined text-lg ${file.is_dir ? 'text-primary' : 'text-slate-500'}`}>{fileIcon(file)}</span>
                    <span className="text-slate-200 font-mono text-sm truncate max-w-[260px]">{file.name}</span>
                </div>
            </td>
            <td className="py-3 px-4 text-slate-500 font-mono text-xs">{formatDate(file.modified)}</td>
            <td className="py-3 px-4 text-slate-500 font-mono text-xs">{file.is_dir ? '—' : formatBytes(file.size)}</td>
            <td className="py-3 px-4 text-slate-500 font-mono text-xs uppercase">{file.is_dir ? 'DIR' : (getExt(file.name) || 'FILE')}</td>
            <td className="py-3 px-4 text-right" onClick={e => e.stopPropagation()}>
                <button onClick={e => handleDelete(file, e)} className="opacity-0 group-hover:opacity-100 text-slate-600 hover:text-primary transition-all">
                    <span className="material-symbols-outlined text-sm">delete</span>
                </button>
            </td>
        </tr>
    );

    const FileGridCard = ({ file }: { file: FileItem }) => {
        const rel = currentPath ? `${currentPath}/${file.name}` : file.name;
        const thumb = gridCache[rel];
        return (
            <div className="bg-[#141414] border border-[#2d2d2d] hover:border-primary/40 transition-all cursor-pointer group relative overflow-hidden"
                onClick={() => handleFileClick(file)}>
                {/* Thumbnail or icon */}
                <div className="h-36 bg-[#0f0f0f] flex items-center justify-center overflow-hidden">
                    {thumb && isImage(file.name) ? (
                        <img src={thumb} alt={file.name} className="w-full h-full object-cover" />
                    ) : (
                        <span className={`material-symbols-outlined text-5xl ${file.is_dir ? 'text-primary/50' : 'text-slate-700'}`}>{fileIcon(file)}</span>
                    )}
                </div>
                <div className="p-3">
                    <p className="text-slate-200 text-xs font-mono truncate">{file.name}</p>
                    <p className="text-slate-600 text-[10px] mt-1">{file.is_dir ? 'FOLDER' : formatBytes(file.size)}</p>
                </div>
                <button onClick={e => handleDelete(file, e)}
                    className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 bg-black/70 text-slate-400 hover:text-primary p-1 transition-all">
                    <span className="material-symbols-outlined text-sm">delete</span>
                </button>
            </div>
        );
    };

    const OfflineBanner = () => (
        <div className="bg-[#141414] border border-primary/30 p-10 text-center rounded">
            <span className="material-symbols-outlined text-5xl text-primary/40 mb-3 block">usb_off</span>
            <p className="text-primary text-sm font-bold uppercase tracking-widest">Agent Offline</p>
            <p className="text-slate-500 text-xs mt-2">Open the DriveNet Windows app, select your USB, and press GO ONLINE</p>
        </div>
    );

    const FileTable = ({ items }: { items: FileItem[] }) => (
        <table className="w-full">
            <thead><tr className="border-b border-[#2d2d2d] bg-[#0f0f0f]">
                {['RESOURCE NAME', 'LAST MODIFIED', 'SIZE', 'TYPE', ''].map(h => (
                    <th key={h} className="text-left py-3 px-4 text-[9px] font-bold tracking-[0.2em] text-slate-600 uppercase">{h}</th>
                ))}
            </tr></thead>
            <tbody>
                {loading ? <tr><td colSpan={5} className="text-center py-12 text-slate-700 text-xs uppercase tracking-widest">SCANNING...</td></tr>
                    : items.length === 0 ? <tr><td colSpan={5} className="text-center py-12 text-slate-700 text-xs uppercase tracking-widest">NO FILES FOUND</td></tr>
                        : items.map(f => <FileListRow key={f.name} file={f} />)}
            </tbody>
        </table>
    );

    return (
        <div className="flex h-screen bg-[#0e0e0e] text-slate-300 font-sans overflow-hidden">
            <div className="absolute inset-0 pointer-events-none opacity-5 scanline z-50"></div>

            {/* Toast */}
            {toast && (
                <div className={`fixed top-4 right-4 z-[200] px-5 py-3 text-sm font-bold uppercase tracking-widest border shadow-2xl animate-pulse-1
          ${toast.ok ? 'bg-green-900/90 border-green-500/50 text-green-300' : 'bg-[#1a0a0a] border-primary text-primary'}`}>
                    {toast.msg}
                </div>
            )}

            {/* Sidebar */}
            <aside className="w-60 bg-[#141414] border-r border-[#222] hidden md:flex flex-col z-20 shrink-0">
                <div className="p-5 border-b border-[#222]">
                    <div className="flex items-center gap-2 mb-1.5">
                        <div className="w-1.5 h-6 bg-primary shrink-0"></div>
                        <h2 className="text-xs font-black text-white uppercase tracking-[0.2em]">PROTOCOL: CLOUD</h2>
                    </div>
                    <div className="flex items-center gap-2 pl-3.5 mt-1">
                        <div className={`w-2 h-2 rounded-full shrink-0 ${agentOnline ? 'bg-green-500 shadow-[0_0_8px_#22c55e]' : 'bg-red-500 animate-pulse'}`}></div>
                        <p className="text-[9px] text-slate-500 uppercase tracking-widest">{agentOnline ? 'AGENT ONLINE · SYNCED' : 'AGENT OFFLINE'}</p>
                    </div>
                </div>
                <nav className="flex-1 py-4 flex flex-col gap-1 px-3">
                    <NavBtn tab="dashboard" icon="dashboard" label="Dashboard" />
                    <NavBtn tab="allfiles" icon="folder_open" label="All Files" />
                    <NavBtn tab="recent" icon="history" label="Recent Activity" />
                    <NavBtn tab="shared" icon="share" label="Shared Comms" />
                </nav>
                <div className="p-5 border-t border-[#222] space-y-3">
                    <div className="flex items-center gap-3">
                        <div className="w-9 h-9 bg-[#1a1a1a] border border-primary/40 flex items-center justify-center shrink-0">
                            <span className="material-symbols-outlined text-xl text-slate-500">person</span>
                        </div>
                        <div className="min-w-0">
                            <p className="text-xs font-black text-white uppercase tracking-widest truncate">{userEmail.split('@')[0]}</p>
                            <p className="text-[9px] text-primary uppercase font-bold tracking-widest">RANK: RADIANT</p>
                        </div>
                    </div>
                    <button onClick={handleLogout} className="w-full text-slate-500 border border-[#2d2d2d] hover:border-primary hover:text-primary transition-all p-2 flex justify-center items-center gap-2 font-bold text-[10px] uppercase tracking-widest">
                        <span className="material-symbols-outlined text-xs">logout</span>
                        DISCONNECT SESSION
                    </button>
                </div>
            </aside>

            {/* Main */}
            <main className="flex-1 flex flex-col h-screen overflow-y-auto bg-[#0e0e0e]">
                {/* Header */}
                <header className="sticky top-0 z-30 flex flex-wrap items-center justify-between px-6 py-3 border-b border-[#222] bg-[#0e0e0e]/95 backdrop-blur gap-3">
                    <div>
                        <div className="flex items-center gap-2">
                            <div className="p-1 border border-primary/60"><span className="material-symbols-outlined text-primary text-lg">shield</span></div>
                            <h1 className="text-sm font-black tracking-widest uppercase italic">CLOUDD<span className="text-primary">RIVE</span> MANAGER</h1>
                            {agentOnline && <span className="text-[9px] font-bold tracking-widest text-green-400 border border-green-500/20 bg-green-500/5 px-2 py-0.5">SYNCED</span>}
                        </div>
                    </div>
                    <div className="flex gap-2 items-center">
                        <input type="file" id="fileUpload" className="hidden" onChange={handleUpload} />
                        <button onClick={() => document.getElementById('fileUpload')?.click()}
                            className="bg-primary text-white px-5 py-2.5 font-bold text-xs uppercase tracking-widest hover:bg-[#ff3042] transition-colors flex items-center gap-2 btn-slanted">
                            <span className="material-symbols-outlined text-sm">upload</span>
                            UPLOAD DATA
                        </button>
                    </div>
                </header>

                {/* Upload progress */}
                {Object.entries(uploadProgress).map(([name, pct]) => (
                    <div key={name} className="bg-[#141414] border-b border-[#222] px-6 py-2 flex items-center gap-4">
                        <span className="text-xs font-mono text-primary uppercase truncate flex-1">TRANSMITTING: {name}</span>
                        <div className="w-40 h-1 bg-[#2d2d2d]"><div className="h-full bg-primary transition-all" style={{ width: `${pct}%` }}></div></div>
                        <span className="text-xs font-mono text-primary">{pct}%</span>
                    </div>
                ))}

                <div className="flex-1 p-5 pb-10 space-y-6">

                    {/* DASHBOARD */}
                    {activeTab === 'dashboard' && (
                        <>
                            <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
                                <div className="bg-[#141414] border border-[#222] p-5">
                                    <p className="text-[9px] text-slate-600 uppercase tracking-widest mb-2">Storage Capacity</p>
                                    <p className="text-3xl font-black text-white">{formatBytes(storageUsed)}<span className="text-xs text-slate-500 ml-1">used</span></p>
                                    <p className="text-xs text-slate-600 mt-0.5">of {formatBytes(sysStats?.storageTotal ?? 0)} • {formatBytes(sysStats?.storageAvailable ?? 0)} free</p>
                                    <div className="mt-3 h-1 bg-[#2d2d2d]"><div className="h-full bg-primary" style={{ width: `${storagePct.toFixed(0)}%` }}></div></div>
                                </div>
                                <div className="bg-[#141414] border border-[#222] p-5">
                                    <p className="text-[9px] text-slate-600 uppercase tracking-widest mb-2">Sync Frequency</p>
                                    <p className="text-3xl font-black text-white">{sysStats ? Math.round((sysStats.up + sysStats.down) / 2) : '—'}<span className="text-xs text-slate-500 ml-1">ms / Realtime</span></p>
                                    <p className={`text-[10px] font-bold uppercase tracking-widest mt-2 ${agentOnline ? 'text-green-400' : 'text-red-400'}`}>
                                        ● {agentOnline ? 'OPTIMAL CONNECTION STATE' : 'AGENT DISCONNECTED'}
                                    </p>
                                </div>
                                <div className="bg-[#141414] border border-[#222] p-5">
                                    <p className="text-[9px] text-slate-600 uppercase tracking-widest mb-2">Activity Log</p>
                                    <p className="text-3xl font-black text-white">{activity.length}<span className="text-xs text-slate-500 ml-1">Transfers</span></p>
                                    <p className="text-[10px] text-slate-600 uppercase tracking-widest mt-2">SECURITY LEVEL: HIGH</p>
                                </div>
                            </div>

                            {/* Live file browser */}
                            <div className="bg-[#141414] border border-[#222]">
                                <div className="px-5 py-3 border-b border-[#222] flex flex-wrap items-center gap-3">
                                    <div className="flex items-center gap-2 flex-1 min-w-0">
                                        <span className="material-symbols-outlined text-slate-600 text-sm">search</span>
                                        <span className="text-xs font-mono text-slate-500 uppercase tracking-widest truncate">
                                            SCANNING: {currentPath ? currentPath.toUpperCase() : 'ROOT:/'}
                                        </span>
                                        {agentOnline && <span className="text-[8px] text-green-500 animate-pulse">● LIVE</span>}
                                    </div>
                                    {currentPath && (
                                        <button onClick={navigateUp} className="text-slate-500 hover:text-primary text-xs flex items-center gap-1 border border-[#333] px-2 py-1 hover:border-primary/30">
                                            <span className="material-symbols-outlined text-xs">arrow_back</span> BACK
                                        </button>
                                    )}
                                </div>
                                {!agentOnline ? <div className="p-8"><OfflineBanner /></div> : <FileTable items={filteredFiles} />}
                            </div>
                        </>
                    )}

                    {/* ALL FILES */}
                    {activeTab === 'allfiles' && (
                        <>
                            <div className="flex flex-wrap items-center gap-3 justify-between">
                                <div>
                                    <h2 className="text-lg font-black uppercase tracking-widest text-white">ALL FILES</h2>
                                    <p className="text-xs text-slate-600 font-mono mt-0.5">{currentPath ? `PATH: /${currentPath}` : 'PATH: ROOT:/'}</p>
                                </div>
                                <div className="flex items-center gap-2">
                                    <input value={filter} onChange={e => setFilter(e.target.value)} placeholder="FILTER FILES..." className="bg-[#141414] border border-[#333] text-slate-300 placeholder:text-slate-700 px-3 py-1.5 text-xs font-mono focus:outline-none focus:border-primary/50 w-40" />
                                    <button onClick={() => setViewMode('list')} className={`p-1.5 border ${viewMode === 'list' ? 'border-primary text-primary' : 'border-[#333] text-slate-600 hover:text-slate-300'}`}>
                                        <span className="material-symbols-outlined text-sm">list</span>
                                    </button>
                                    <button onClick={() => setViewMode('grid')} className={`p-1.5 border ${viewMode === 'grid' ? 'border-primary text-primary' : 'border-[#333] text-slate-600 hover:text-slate-300'}`}>
                                        <span className="material-symbols-outlined text-sm">grid_view</span>
                                    </button>
                                    {currentPath && (
                                        <button onClick={navigateUp} className="text-xs font-mono text-slate-400 hover:text-primary flex items-center gap-1 border border-[#333] hover:border-primary/30 px-3 py-1.5">
                                            <span className="material-symbols-outlined text-sm">arrow_back</span> BACK
                                        </button>
                                    )}
                                    <button onClick={() => fetchFiles(currentPath)} className="text-xs font-mono text-slate-400 hover:text-primary flex items-center gap-1 border border-[#333] hover:border-primary/30 px-3 py-1.5">
                                        <span className="material-symbols-outlined text-sm">refresh</span>
                                    </button>
                                </div>
                            </div>

                            {!agentOnline ? <OfflineBanner /> : viewMode === 'list' ? (
                                <div className="bg-[#141414] border border-[#222]"><FileTable items={filteredFiles} /></div>
                            ) : (
                                <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-3">
                                    {loading ? (
                                        Array.from({ length: 10 }).map((_, i) => <div key={i} className="bg-[#141414] border border-[#222] h-44 animate-pulse" />)
                                    ) : filteredFiles.length === 0 ? (
                                        <div className="col-span-full text-center py-12 text-slate-700 text-xs uppercase tracking-widest">DRIVE IS EMPTY</div>
                                    ) : filteredFiles.map(f => <FileGridCard key={f.name} file={f} />)}
                                </div>
                            )}
                        </>
                    )}

                    {/* RECENT ACTIVITY */}
                    {activeTab === 'recent' && (
                        <>
                            <div className="flex items-center justify-between">
                                <div>
                                    <h2 className="text-lg font-black uppercase tracking-widest text-white">RECENT ACTIVITY</h2>
                                    <p className="text-xs text-slate-600 mt-0.5">Persisted for this browser session</p>
                                </div>
                                <button onClick={() => { setActivity([]); sessionStorage.removeItem('dn_activity'); }}
                                    className="text-[10px] font-bold text-slate-500 hover:text-primary uppercase tracking-widest border border-[#2d2d2d] hover:border-primary/30 px-3 py-1.5 transition-all">
                                    CLEAR LOG
                                </button>
                            </div>
                            {activity.length === 0 ? (
                                <div className="bg-[#141414] border border-[#222] p-12 text-center">
                                    <span className="material-symbols-outlined text-4xl text-slate-800 mb-3 block">history</span>
                                    <p className="text-slate-700 text-xs uppercase tracking-widest">NO TRANSFERS YET</p>
                                    <p className="text-slate-800 text-xs mt-2">Upload or delete a file to see activity here</p>
                                </div>
                            ) : (
                                <div className="bg-[#141414] border border-[#222]">
                                    <table className="w-full">
                                        <thead><tr className="border-b border-[#222] bg-[#0f0f0f]">
                                            {['FILE', 'ACTION', 'TIME', 'SIZE'].map(h => (
                                                <th key={h} className="text-left py-3 px-4 text-[9px] font-bold tracking-[0.2em] text-slate-600 uppercase">{h}</th>
                                            ))}
                                        </tr></thead>
                                        <tbody>
                                            {activity.map((a, i) => (
                                                <tr key={i} className="border-b border-[#1a1a1a] hover:bg-white/[0.02]">
                                                    <td className="py-3 px-4 font-mono text-sm text-slate-300 truncate max-w-[200px]">{a.name}</td>
                                                    <td className="py-3 px-4">
                                                        <span className={`text-[9px] font-bold uppercase tracking-widest px-2 py-1 ${a.action === 'UPLOADED' ? 'bg-green-500/10 text-green-400' : 'bg-red-500/10 text-red-400'}`}>
                                                            {a.action}
                                                        </span>
                                                    </td>
                                                    <td className="py-3 px-4 font-mono text-xs text-slate-500">{formatDate(a.time)}</td>
                                                    <td className="py-3 px-4 font-mono text-xs text-slate-500">{formatBytes(a.size)}</td>
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                </div>
                            )}
                        </>
                    )}

                    {/* SHARED COMMS */}
                    {activeTab === 'shared' && (
                        <>
                            <h2 className="text-lg font-black uppercase tracking-widest text-white">SHARED COMMS</h2>
                            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                                <div className="bg-[#141414] border border-[#222] p-6">
                                    <div className="flex items-center gap-2 mb-3">
                                        <span className="material-symbols-outlined text-primary">account_circle</span>
                                        <h3 className="text-xs font-bold uppercase tracking-widest text-white">CONNECTED ACCOUNT</h3>
                                    </div>
                                    <p className="text-sm text-slate-300 font-mono">{userEmail}</p>
                                    <p className="text-xs text-slate-600 mt-2">Google account is the access key for this USB drive</p>
                                </div>
                                <div className="bg-[#141414] border border-[#222] p-6">
                                    <div className="flex items-center gap-2 mb-3">
                                        <span className="material-symbols-outlined text-primary">link</span>
                                        <h3 className="text-xs font-bold uppercase tracking-widest text-white">SHARE FILES</h3>
                                    </div>
                                    <p className="text-xs text-slate-500 mb-3">Browse to a file, click it, and generate a share link</p>
                                    <button onClick={() => setActiveTab('allfiles')} className="text-xs font-bold text-primary border border-primary/30 px-4 py-2 hover:bg-primary/10 uppercase tracking-widest">
                                        BROWSE FILES →
                                    </button>
                                </div>
                            </div>
                            <div className="bg-[#141414] border border-[#222]/40 p-10 text-center">
                                <span className="material-symbols-outlined text-5xl text-slate-800 mb-3 block">folder_shared</span>
                                <p className="text-slate-700 text-xs uppercase tracking-widest">Shared links will appear here — coming soon</p>
                            </div>
                        </>
                    )}
                </div>
            </main>

            {/* Preview Modal */}
            {(previewUrl || previewLoading) && (
                <div className="fixed inset-0 z-[200] bg-black/95 flex items-center justify-center p-6"
                    onClick={() => { setPreviewUrl(null); setPreviewType(null); setPreviewLoading(false); }}>
                    <div className="max-w-5xl max-h-[90vh] w-full relative" onClick={e => e.stopPropagation()}>
                        <div className="flex items-center justify-between mb-3">
                            <div className="flex items-center gap-4">
                                <span className="text-xs font-mono text-slate-400 uppercase tracking-widest">{previewName}</span>
                                {previewType === 'video' && (
                                    <div className="flex bg-[#141414] border border-[#333] rounded overflow-hidden">
                                        <button onClick={() => setVideoQuality('original')} className={`px-3 py-1 text-[10px] font-bold uppercase tracking-widest transition-colors ${videoQuality === 'original' ? 'bg-primary text-white' : 'text-slate-500 hover:text-white'}`}>Original Quality</button>
                                        <button onClick={() => setVideoQuality('low')} className={`px-3 py-1 text-[10px] font-bold uppercase tracking-widest transition-colors ${videoQuality === 'low' ? 'bg-primary text-white' : 'text-slate-500 hover:text-white'}`}>Auto (Data Saver)</button>
                                    </div>
                                )}
                            </div>
                            <button onClick={() => { setPreviewUrl(null); setPreviewType(null); setPreviewLoading(false); }}
                                className="text-slate-500 hover:text-white border border-[#333] hover:border-primary px-2 py-1 transition-all">
                                <span className="material-symbols-outlined text-sm">close</span>
                            </button>
                        </div>
                        {previewLoading ? (
                            <div className="h-64 flex items-center justify-center">
                                <div className="text-center">
                                    <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin mx-auto mb-3"></div>
                                    <p className="text-xs text-slate-500 uppercase tracking-widest">Loading from cache...</p>
                                </div>
                            </div>
                        ) : (
                            <>
                                {previewType === 'image' && previewUrl && <img src={previewUrl} alt={previewName ?? ''} className="max-h-[80vh] max-w-full mx-auto object-contain" />}
                                {previewType === 'video' && previewUrl && <video src={previewUrl} controls className="max-h-[80vh] max-w-full mx-auto" autoPlay />}
                                {previewType === 'pdf' && previewUrl && <iframe src={previewUrl} className="w-full h-[80vh]" title={previewName ?? ''} />}
                                {previewType === 'text' && (
                                    <div className="bg-[#141414] border border-[#333] p-6 max-h-[80vh] overflow-y-auto">
                                        <pre className="text-xs font-mono text-slate-300 w-full whitespace-pre-wrap">{previewText}</pre>
                                    </div>
                                )}
                            </>
                        )}
                    </div>
                </div>
            )}
        </div>
    );
};

export default FileBrowser;
