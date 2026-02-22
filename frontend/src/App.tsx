
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { GoogleOAuthProvider } from '@react-oauth/google';
import Landing from './pages/Landing';
import Login from './pages/Login';
import FileBrowser from './components/FileBrowser';

// Auth guard: redirect to login if no token
function RequireAuth({ children }: { children: React.ReactElement }) {
  const token = localStorage.getItem('drivenet_token');
  if (!token) return <Navigate to="/login" replace />;
  return children;
}

// Redirect to dashboard if already logged in — but skip if this is the Flutter agent mode
function RedirectIfAuth({ children }: { children: React.ReactElement }) {
  const token = localStorage.getItem('drivenet_token');
  const params = new URLSearchParams(window.location.search);
  const isAgentMode = params.get('agent') === 'true';
  // If agent mode, always show the login page regardless of web session
  if (token && !isAgentMode) return <Navigate to="/dashboard" replace />;
  return children;
}

function App() {
  const clientId = import.meta.env.VITE_GOOGLE_CLIENT_ID || 'dummy-client-id';

  return (
    <GoogleOAuthProvider clientId={clientId}>
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<Landing />} />
          <Route path="/login" element={<RedirectIfAuth><Login /></RedirectIfAuth>} />
          <Route path="/dashboard/*" element={<RequireAuth><FileBrowser /></RequireAuth>} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </GoogleOAuthProvider>
  );
}

export default App;

