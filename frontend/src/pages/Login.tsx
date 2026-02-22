import React, { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import axios from 'axios';
import { GoogleLogin } from '@react-oauth/google';

const Login: React.FC = () => {
    const navigate = useNavigate();
    const [searchParams] = useSearchParams();
    const isAgentMode = searchParams.get('agent') === 'true';

    const [error, setError] = useState('');
    const [agentStatus, setAgentStatus] = useState('');

    // If in agent mode, show a banner
    useEffect(() => {
        if (isAgentMode) {
            setAgentStatus('FLUTTER AGENT MODE — Sign in to activate device sync');
        }
    }, [isAgentMode]);

    const sendTokenToAgent = async (token: string, user: string) => {
        if (!isAgentMode) return;
        try {
            setAgentStatus('SENDING TOKEN TO AGENT...');
            await fetch('http://localhost:9292/token', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ token, user }),
            });
            setAgentStatus('✓ AGENT AUTHENTICATED — You can close this window');
        } catch {
            // Agent server may have already closed, that's fine
            setAgentStatus('✓ AUTHENTICATED');
        }
    };

    const handleGoogleSuccess = async (credentialResponse: any) => {
        setError('');
        try {
            const res = await axios.post('http://localhost:8000/api/auth/login', {
                google_token: credentialResponse.credential
            });
            if (res.data.token) {
                localStorage.setItem('drivenet_token', res.data.token);
                await sendTokenToAgent(res.data.token, res.data.user);
                if (!isAgentMode) navigate('/dashboard');
            }
        } catch (err: any) {
            setError(err.response?.data?.error || 'Google Authentication Failed');
        }
    };

    return (
        <div className="bg-[#172535] dark:bg-[#0f1923] text-slate-900 dark:text-slate-100 min-h-screen flex flex-col overflow-hidden font-display">
            {/* Background Layers */}
            <div className="fixed inset-0 grid-bg opacity-40 pointer-events-none" style={{
                backgroundImage: `linear-gradient(to right, rgba(255, 71, 87, 0.05) 1px, transparent 1px),
                                    linear-gradient(to bottom, rgba(255, 71, 87, 0.05) 1px, transparent 1px)`,
                backgroundSize: '40px 40px'
            }}></div>
            <div className="fixed inset-0 bg-gradient-to-tr from-[#0f1923] via-transparent to-primary/5 pointer-events-none"></div>

            <header className="relative z-10 flex items-center justify-between px-6 py-4 border-b border-primary/20 bg-[#0f1923]/80 backdrop-blur-md">
                <div className="flex items-center gap-4">
                    <div className="p-1 border border-primary text-primary">
                        <span className="material-symbols-outlined text-2xl">shield</span>
                    </div>
                    <h2 className="text-xl font-bold tracking-widest uppercase">DriveNet <span className="text-primary">Command</span></h2>
                </div>
                <div className="hidden md:flex items-center gap-6 text-xs font-bold tracking-[0.2em] text-slate-400 uppercase">
                    <div className="flex items-center gap-2">
                        <span className="w-2 h-2 rounded-full bg-green-500 shadow-[0_0_8px_#22c55e]"></span>
                        <span>Cloud Relay Online</span>
                    </div>
                </div>
            </header>

            {agentStatus && (
                <div className="relative z-10 text-center py-2 text-xs font-bold tracking-widest uppercase bg-primary/10 border-b border-primary/30 text-primary">
                    {agentStatus}
                </div>
            )}

            <main className="relative z-10 flex-grow flex items-center justify-center p-6">
                <div className="w-full max-w-md relative">
                    {/* Decorative corners */}
                    <div className="absolute -top-0.5 -left-0.5 w-5 h-5 border-t-2 border-l-2 border-primary z-20"></div>
                    <div className="absolute -bottom-0.5 -right-0.5 w-5 h-5 border-b-2 border-r-2 border-primary z-20"></div>

                    <div className="bg-[#1a1a1c]/90 dark:bg-[#0f1923]/90 backdrop-blur-xl border border-white/10 shadow-2xl p-8 rounded relative z-10">
                        <div className="mb-8 border-b border-primary/20 pb-6 relative">
                            <div className="flex justify-between items-start mb-2">
                                <p className="text-[10px] tracking-[0.3em] text-primary font-bold uppercase">Authorization Layer 01</p>
                                <span className="text-[10px] text-slate-500 font-mono">ID: VR-9921</span>
                            </div>
                            <h1 className="text-4xl font-black tracking-tighter uppercase italic">Secure <span className="text-primary">Gateway</span></h1>
                            <p className="text-slate-400 text-sm mt-2 font-medium tracking-tight">AGENT AUTHENTICATION REQUIRED FOR UPLINK</p>
                            <div className="absolute -bottom-[1px] left-0 w-1/3 h-[2px] bg-primary"></div>
                        </div>

                        {error && <div className="mb-6 text-primary text-xs font-bold bg-primary/10 border border-primary/20 p-3 rounded uppercase">{error}</div>}

                        {/* Google Auth Option */}
                        <div className="mb-8 flex flex-col items-center">
                            <p className="text-xs uppercase tracking-[0.2em] text-slate-500 font-bold mb-4">Fast Uplink</p>
                            <GoogleLogin
                                onSuccess={handleGoogleSuccess}
                                onError={() => setError('Google Log in failed')}
                                theme="filled_black"
                                shape="pill"
                                text="continue_with"
                            />
                        </div>

                    </div>
                </div>
            </main>
        </div>
    );
};

export default Login;
