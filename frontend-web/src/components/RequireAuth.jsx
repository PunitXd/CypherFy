import { Navigate } from 'react-router-dom';
import { useAuth } from '../store/auth';

// Gate for authed-only routes. While the initial bootstrap resolves we render a
// blank room rather than flashing the login screen.
export default function RequireAuth({ children }) {
  const status = useAuth((s) => s.status);
  if (status === 'idle' || status === 'loading') return <div className="room" />;
  if (status !== 'authed') return <Navigate to="/" replace />;
  return children;
}
