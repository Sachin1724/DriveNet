import React from 'react';
import { useNavigate } from 'react-router-dom';

const Landing: React.FC = () => {
    const navigate = useNavigate();

    return (
        <div className="bg-background-light dark:bg-background-dark font-display text-slate-900 dark:text-slate-100 overflow-x-hidden selection:bg-primary selection:text-white min-h-screen">
            {/* Tactical Scanline Overlay */}
            <div className="fixed inset-0 pointer-events-none scanline opacity-30 z-50"></div>
            <div className="relative flex min-h-screen flex-col">

                {/* Navigation */}
                <header className="sticky top-0 z-40 w-full border-b border-primary/20 bg-background-dark/80 backdrop-blur-md px-6 lg:px-20 py-4">
                    <div className="max-w-7xl mx-auto flex items-center justify-between">
                        <div className="flex items-center gap-3">
                            <div className="p-1 border-2 border-primary rotate-45">
                                <span className="material-symbols-outlined text-primary -rotate-45 block text-2xl">grid_view</span>
                            </div>
                            <h2 className="text-2xl font-black tracking-tighter italic text-white pr-2">Drive<span className="text-primary font-light">Net</span></h2>
                        </div>
                        <nav className="hidden md:flex items-center gap-10">
                            <a className="text-xs font-bold tracking-[0.2em] uppercase hover:text-primary transition-colors text-white" href="#">Features</a>
                            <a className="text-xs font-bold tracking-[0.2em] uppercase hover:text-primary transition-colors text-white" href="#">Security</a>
                            <a className="text-xs font-bold tracking-[0.2em] uppercase hover:text-primary transition-colors text-white" href="#">Docs</a>
                        </nav>
                        <div className="flex items-center gap-6">
                            <button
                                onClick={() => navigate('/login')}
                                className="bg-primary text-white px-8 py-2 font-black italic tracking-widest text-sm btn-slanted hover:brightness-110 transition-all active:scale-95"
                            >
                                START UPLINK
                            </button>
                        </div>
                    </div>
                </header>

                <main className="flex-1">
                    {/* Hero Section */}
                    <section className="relative pt-20 pb-40 px-6 lg:px-20 overflow-hidden bg-background-dark">
                        <div className="absolute inset-0 opacity-20 pointer-events-none">
                            <div className="absolute top-0 right-0 w-1/2 h-full bg-gradient-to-l from-primary/20 to-transparent skew-x-12"></div>
                        </div>
                        <div className="max-w-7xl mx-auto grid lg:grid-cols-2 gap-16 items-center relative z-10">
                            <div className="flex flex-col gap-8">
                                <div className="inline-flex items-center">
                                    <span className="bg-primary text-white text-[10px] font-black px-3 py-1 tracking-[0.3em] uppercase italic flex items-center gap-2">
                                        <span className="w-1.5 h-1.5 bg-white rounded-full animate-pulse"></span>
                                        V2.0 NOW AVAILABLE
                                    </span>
                                </div>
                                <h1 className="text-6xl md:text-8xl font-black italic tracking-tighter leading-[0.9] uppercase text-slate-100">
                                    Turn Any USB <br /> Drive into a <br /> <span className="text-primary">Global Cloud</span>
                                </h1>
                                <p className="text-slate-400 text-lg max-w-lg font-medium leading-relaxed border-l-2 border-primary/40 pl-6 uppercase tracking-wider text-sm">
                                    Experience the evolution of portable cloud infrastructure with tactical-grade encryption and global access. Deploy instantly from any terminal.
                                </p>
                                <div className="flex flex-wrap gap-4 pt-4">
                                    <button
                                        onClick={() => navigate('/login')}
                                        className="group relative px-10 py-4 bg-primary text-white font-black italic tracking-widest btn-slanted overflow-hidden transition-all hover:pr-14"
                                    >
                                        <span className="relative z-10">CONNECT NODE</span>
                                        <span className="material-symbols-outlined absolute right-4 top-1/2 -translate-y-1/2 opacity-0 group-hover:opacity-100 transition-all text-xl">bolt</span>
                                    </button>
                                </div>
                            </div>
                            <div className="relative group">
                                <div className="absolute -inset-4 bg-primary/10 blur-3xl rounded-full group-hover:bg-primary/20 transition-all duration-700"></div>
                                <div className="relative aspect-video rounded-lg overflow-hidden border-2 border-primary/20 bg-surface-dark group-hover:border-primary/50 transition-all">
                                    <img className="w-full h-full object-cover grayscale contrast-125 brightness-75 group-hover:grayscale-0 transition-all duration-700" alt="Tech" src="https://lh3.googleusercontent.com/aida-public/AB6AXuC7YfZOA1MIGMeS-d90AigEyxvlE3dNRchkKk_Fp5MCr6fsSVZrJp8G5uUHv0EIHnYa-YT1umy21nGkkWYVUr1P8GsMMrks-ekX914InqJ8hImcxyJA4-crpk2hFltFAMZnxux3YHEthb-TPFODjr6pWyVPARliC__qs0_lDOyH3W7tR1EsnDcVj9xL0pNuDfpR4IdV9crum9KulEcBYbpGcYzswRONbwu0NmMg0K9m0im6pre0hxHprZ2NdIEHM7V0C4VOK_Xsb3G0" />
                                    <div className="absolute top-4 left-4 flex gap-2">
                                        <div className="w-2 h-2 bg-primary animate-ping"></div>
                                        <span className="text-[10px] text-primary font-bold tracking-tighter">ESTABLISHING UPLINK...</span>
                                    </div>
                                </div>
                                <div className="absolute -top-4 -right-4 w-16 h-16 border-t-2 border-r-2 border-primary/40"></div>
                                <div className="absolute -bottom-4 -left-4 w-16 h-16 border-b-2 border-l-2 border-primary/40"></div>
                            </div>
                        </div>
                    </section>

                    {/* Features Section */}
                    <section className="relative bg-surface-dark py-32 px-6 lg:px-20 -mt-10 hero-skew">
                        <div className="max-w-7xl mx-auto">
                            <div className="flex flex-col gap-4 mb-20">
                                <div className="flex items-center gap-4">
                                    <h2 className="text-primary text-sm font-black tracking-[0.5em] uppercase">SYSTEM CAPABILITIES</h2>
                                    <div className="h-[1px] flex-1 bg-gradient-to-r from-primary/40 to-transparent"></div>
                                </div>
                                <h3 className="text-4xl md:text-6xl font-black italic uppercase tracking-tighter text-white">ELITE PERFORMANCE</h3>
                            </div>
                            <div className="grid md:grid-cols-3 gap-8">
                                <div className="group relative p-8 bg-background-dark border-r-2 border-b-2 border-slate-800 hover:border-primary card-angle transition-all duration-300">
                                    <div className="mb-6 inline-flex w-14 h-14 items-center justify-center bg-primary/10 text-primary group-hover:bg-primary group-hover:text-white transition-all">
                                        <span className="material-symbols-outlined text-3xl">lock</span>
                                    </div>
                                    <h4 className="text-xl font-black italic uppercase mb-4 text-white tracking-tight">Tactical Security</h4>
                                    <p className="text-slate-400 font-medium leading-relaxed text-sm group-hover:text-slate-200 transition-colors">
                                        Secure WebSocket tunneling with JWT authentication ensuring pure point-to-point data streaming.
                                    </p>
                                </div>
                                <div className="group relative p-8 bg-background-dark border-r-2 border-b-2 border-slate-800 hover:border-primary card-angle transition-all duration-300">
                                    <div className="mb-6 inline-flex w-14 h-14 items-center justify-center bg-primary/10 text-primary group-hover:bg-primary group-hover:text-white transition-all">
                                        <span className="material-symbols-outlined text-3xl">public</span>
                                    </div>
                                    <h4 className="text-xl font-black italic uppercase mb-4 text-white tracking-tight">Global Portability</h4>
                                    <p className="text-slate-400 font-medium leading-relaxed text-sm group-hover:text-slate-200 transition-colors">
                                        Plug into any terminal globally and access your persistent workspace instantly with zero port forwarding.
                                    </p>
                                </div>
                                <div className="group relative p-8 bg-background-dark border-r-2 border-b-2 border-slate-800 hover:border-primary card-angle transition-all duration-300">
                                    <div className="mb-6 inline-flex w-14 h-14 items-center justify-center bg-primary/10 text-primary group-hover:bg-primary group-hover:text-white transition-all">
                                        <span className="material-symbols-outlined text-3xl">bolt</span>
                                    </div>
                                    <h4 className="text-xl font-black italic uppercase mb-4 text-white tracking-tight">Live Telemetry</h4>
                                    <p className="text-slate-400 font-medium leading-relaxed text-sm group-hover:text-slate-200 transition-colors">
                                        Monitor the background electron service in real-time right from your browser dashboard.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </section>
                </main>

                <footer className="bg-background-dark border-t border-slate-800 py-10 px-6 lg:px-20 text-center">
                    <p className="text-[10px] text-slate-600 font-bold tracking-[0.3em] uppercase">© 2026 DRIVENET PROTOCOL V2.0 // ALL RIGHTS RESERVED</p>
                </footer>
            </div>
        </div>
    );
};

export default Landing;
