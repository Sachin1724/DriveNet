import React, { useState } from 'react';
import { useNavigate, Outlet, useLocation } from 'react-router-dom';

const Dashboard: React.FC = () => {
    const navigate = useNavigate();
    const location = useLocation();
    const [isSidebarOpen, setIsSidebarOpen] = useState(false);

    // Logout handling
    const handleLogout = () => {
        localStorage.removeItem('drivenet_token');
        navigate('/login');
    };

    return (
        <div className="bg-[#f8f5f6] dark:bg-[#0a0505] font-display text-slate-900 dark:text-slate-100 selection:bg-primary/40 selection:text-white relative flex min-h-screen w-full flex-col overflow-x-hidden">
            {/* Background Decor */}
            <div className="fixed inset-0 pointer-events-none opacity-5" style={{
                backgroundImage: 'radial-gradient(circle, #ff4757 1px, transparent 1px)',
                backgroundSize: '30px 30px'
            }}></div>
            <div className="fixed inset-0 scanlines pointer-events-none"></div>

            {/* Top Navigation */}
            <header className="relative z-20 flex items-center justify-between border-b border-[#2d1b1d] bg-[#0a0505]/80 backdrop-blur-md px-4 sm:px-6 py-3">
                <div className="flex items-center gap-4 sm:gap-6">
                    <button
                        className="md:hidden text-primary hover:text-white transition-colors"
                        onClick={() => setIsSidebarOpen(!isSidebarOpen)}
                    >
                        <span className="material-symbols-outlined text-[28px]">menu</span>
                    </button>
                    <div className="flex items-center gap-3">
                        <div className="bg-primary p-1.5 valorant-clip-sm hidden sm:block">
                            <span className="material-symbols-outlined text-[#0a0505] font-bold">terminal</span>
                        </div>
                        <div className="flex flex-col leading-none">
                            <h2 className="text-lg sm:text-xl font-bold tracking-widest text-primary uppercase">System HUD</h2>
                            <span className="text-[9px] sm:text-[10px] tracking-tighter text-primary/60 font-medium whitespace-nowrap">V.2.4.08 PROTOCOL</span>
                        </div>
                    </div>
                </div>

                <div className="flex items-center gap-4 sm:gap-6">
                    <div className="flex gap-2">
                        <button onClick={handleLogout} className="size-8 sm:size-9 flex items-center justify-center bg-[#1a1313] border border-[#2d1b1d] hover:bg-primary/20 hover:border-primary text-slate-400 hover:text-primary transition-colors valorant-clip-sm">
                            <span className="material-symbols-outlined text-[18px] sm:text-[20px]">logout</span>
                        </button>
                    </div>
                    <div className="flex items-center gap-3 pl-4 border-l border-[#2d1b1d]">
                        <div className="text-right hidden sm:block">
                            <p className="text-xs font-bold tracking-widest text-slate-100 uppercase">CYPHER_01</p>
                            <p className="text-[10px] text-primary font-bold uppercase">ADMINISTRATOR</p>
                        </div>
                    </div>
                </div>
            </header>

            <div className="flex flex-1 overflow-hidden relative">
                {/* Mobile Sidebar Overlay */}
                {isSidebarOpen && (
                    <div
                        className="fixed inset-0 bg-black/50 z-20 md:hidden backdrop-blur-sm"
                        onClick={() => setIsSidebarOpen(false)}
                    />
                )}

                {/* Tactical Sidebar */}
                <aside className={`fixed md:relative z-30 w-64 h-full border-r border-[#2d1b1d] bg-[#0a0505] md:bg-[#0a0505]/60 flex flex-col p-4 gap-8 transition-transform duration-300 ease-in-out ${isSidebarOpen ? 'translate-x-0' : '-translate-x-full'} md:translate-x-0`}>
                    <div className="flex flex-col gap-1.5">
                        <p className="text-[10px] font-bold text-slate-600 tracking-[0.3em] uppercase pl-4 mb-2">Navigation</p>
                        <nav className="flex flex-col gap-1">
                            <a onClick={() => { navigate('/dashboard'); setIsSidebarOpen(false); }}
                                className={`group flex items-center gap-3 px-4 py-3 cursor-pointer transition-all ${location.pathname === '/dashboard' ? 'bg-primary/10 text-primary border-r-2 border-primary' : 'text-slate-400 hover:text-slate-100 hover:bg-white/5'}`}>
                                <span className="material-symbols-outlined text-[22px]">dashboard</span>
                                <span className="text-sm font-bold tracking-[0.15em] uppercase">Dashboard</span>
                            </a>
                            <a onClick={() => { navigate('/dashboard/files'); setIsSidebarOpen(false); }}
                                className={`group flex items-center gap-3 px-4 py-3 cursor-pointer transition-all ${location.pathname === '/dashboard/files' ? 'bg-primary/10 text-primary border-r-2 border-primary' : 'text-slate-400 hover:text-slate-100 hover:bg-white/5'}`}>
                                <span className="material-symbols-outlined text-[22px]">folder_open</span>
                                <span className="text-sm font-bold tracking-[0.15em] uppercase">Files</span>
                            </a>
                        </nav>
                    </div>
                    <div className="mt-auto flex flex-col gap-4 p-4 bg-[#1a1313]/50 rounded-xl border border-[#2d1b1d]">
                        <p className="text-[10px] text-slate-500 font-medium italic">Protocol encryption active.</p>
                    </div>
                </aside>

                {/* Main Content Area */}
                <main className="flex-1 overflow-y-auto overflow-x-hidden relative w-full">
                    <Outlet />
                </main>
            </div>
        </div>
    );
};

export default Dashboard;
