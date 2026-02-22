import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import axios from 'axios';

interface SystemStats {
    cpu: number;
    ram: number;
    up: number;
    down: number;
    timestamp?: number;
}

const SystemStatsView: React.FC = () => {
    const API = import.meta.env.VITE_API_URL || 'http://localhost:8000';
    const navigate = useNavigate();
    const [stats, setStats] = useState<SystemStats | null>(null);

    // Simulated stats fetching for dashboard
    useEffect(() => {
        const fetchStats = async () => {
            try {
                const token = localStorage.getItem('drivenet_token');
                if (!token) {
                    navigate('/login');
                    return;
                }

                const res = await axios.get(`${API}/api/fs/stats`, {
                    headers: { 'Authorization': `Bearer ${token}` }
                });

                if (res.data) setStats(res.data);
            } catch (err) {
                console.error("Failed to fetch stats", err);
            }
        };
        fetchStats();
        const interval = setInterval(fetchStats, 2000);
        return () => clearInterval(interval);
    }, [navigate]);

    return (
        <div className="p-6 flex flex-col gap-6 relative h-full">
            {/* Performance Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                <div className="bg-[#1a1313] border border-[#2d1b1d] valorant-clip p-5 relative overflow-hidden group">
                    <div className="absolute top-0 right-0 p-2 opacity-10">
                        <span className="material-symbols-outlined text-4xl">wifi_tethering</span>
                    </div>
                    <p className="text-xs font-bold text-slate-500 uppercase tracking-widest mb-1">Connection</p>
                    <h3 className="text-2xl font-bold text-slate-100 tracking-tight uppercase group-hover:text-primary transition-colors">Online</h3>
                    <div className="mt-4 flex items-center gap-2">
                        <span className="text-[10px] px-2 py-0.5 bg-primary/20 text-primary font-bold rounded">SECURE</span>
                        <span className="text-[10px] text-slate-500 font-mono">WSS</span>
                    </div>
                </div>

                <div className="bg-[#1a1313] border border-[#2d1b1d] valorant-clip p-5 relative overflow-hidden group">
                    <p className="text-xs font-bold text-slate-500 uppercase tracking-widest mb-1">RAM Usage</p>
                    <h3 className="text-2xl font-bold text-slate-100 tracking-tight uppercase">{stats?.ram !== undefined ? stats.ram.toFixed(1) : '--'}<span className="text-primary text-lg">%</span></h3>
                </div>

                <div className="bg-[#1a1313] border border-[#2d1b1d] valorant-clip p-5 relative overflow-hidden group">
                    <p className="text-xs font-bold text-slate-500 uppercase tracking-widest mb-1">Upload Speed</p>
                    <h3 className="text-2xl font-bold text-slate-100 tracking-tight uppercase">{(stats?.up ? stats.up / 1024 / 1024 : 0).toFixed(1)}<span className="text-primary text-sm tracking-normal font-mono ml-1">MB/S</span></h3>
                </div>

                <div className="bg-[#1a1313] border border-[#2d1b1d] valorant-clip p-5 relative overflow-hidden group">
                    <p className="text-xs font-bold text-slate-500 uppercase tracking-widest mb-1">Download Speed</p>
                    <h3 className="text-2xl font-bold text-slate-100 tracking-tight uppercase font-mono tracking-tighter">{(stats?.down ? stats.down / 1024 / 1024 : 0).toFixed(1)}<span className="text-primary text-sm tracking-normal font-mono ml-1">MB/S</span></h3>
                </div>
            </div>

            {/* Network Traffic Graph Section Placeholder */}
            <div className="flex-1 flex flex-col gap-4 bg-[#1a1313]/40 border border-[#2d1b1d] rounded-xl p-6 relative">
                <div className="flex flex-col justify-center items-center h-full opacity-50">
                    <span className="material-symbols-outlined text-6xl text-slate-600 mb-4">monitoring</span>
                    <p className="text-slate-500 tracking-widest uppercase font-bold text-sm">Real-time charts tracking pending integration</p>
                </div>
            </div>
        </div>
    );
};

export default SystemStatsView;
