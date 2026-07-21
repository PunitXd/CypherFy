import { Navigate, Outlet, useLocation } from 'react-router-dom';
import RoomScene from '../components/RoomScene';
import { useAuth } from '../store/auth';

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
    </RoomScene>
  );
}
