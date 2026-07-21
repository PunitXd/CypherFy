import { Navigate, Outlet, useLocation } from 'react-router-dom';
import RoomScene from '../components/RoomScene';
import { useAuth } from '../store/auth';
import { APK_URL } from '../config';

// Wraps every auth screen in the shared lamp/glass scene. Already-authed users
// are bounced to the app — except the password-reset flow, which stays reachable
// when logged in (e.g. from Settings when you don't remember your password).
export default function AuthLayout() {
  const status = useAuth((s) => s.status);
  const loc = useLocation();
  const resetFlow = loc.pathname === '/forgot' || loc.pathname === '/reset';
  if (status === 'authed' && !resetFlow) return <Navigate to="/app" replace />;
  return (
    <RoomScene>
      <Outlet />
      {APK_URL && (
        <a
          href={APK_URL}
          download
          className="apk-download"
          style={{
            position: 'fixed',
            bottom: 16,
            left: '50%',
            transform: 'translateX(-50%)',
            display: 'inline-flex',
            alignItems: 'center',
            gap: 8,
            padding: '8px 16px',
            borderRadius: 999,
            background: 'rgba(255, 255, 255, 0.08)',
            border: '1px solid rgba(255, 255, 255, 0.16)',
            color: '#fff',
            fontSize: 13,
            textDecoration: 'none',
            backdropFilter: 'blur(6px)',
            zIndex: 50,
          }}
        >
          <span aria-hidden="true">⬇️</span> Download for Android
        </a>
      )}
    </RoomScene>
  );
}
