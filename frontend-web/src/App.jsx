import { useEffect } from 'react';
import { createBrowserRouter, RouterProvider, Navigate } from 'react-router-dom';

import AuthLayout from './layouts/AuthLayout';
import RequireAuth from './components/RequireAuth';
import Login from './screens/Login';
import Register from './screens/Register';
import Verify from './screens/Verify';
import Forgot from './screens/Forgot';
import Reset from './screens/Reset';
import AppShell from './screens/AppShell';
import ChatEmpty from './screens/ChatEmpty';
import ChatPane from './screens/ChatPane';
import StandaloneRoom from './screens/StandaloneRoom';
import Search from './screens/Search';
import Profile from './screens/Profile';
import Requests from './screens/Requests';
import Contacts from './screens/Contacts';
import Settings from './screens/Settings';
import EncryptionInfo from './screens/EncryptionInfo';
import { useAuth } from './store/auth';

const router = createBrowserRouter([
  {
    element: <AuthLayout />,
    children: [
      { path: '/', element: <Login /> },
      { path: '/register', element: <Register /> },
      { path: '/verify', element: <Verify /> },
      { path: '/forgot', element: <Forgot /> },
      { path: '/reset', element: <Reset /> },
    ],
  },
  {
    element: (
      <RequireAuth>
        <AppShell />
      </RequireAuth>
    ),
    children: [
      { path: '/app', element: <ChatEmpty /> },
      { path: '/app/dm/:roomId', element: <ChatPane /> },
      { path: '/app/room/:code', element: <ChatPane ephemeral /> },
      { path: '/search', element: <Search /> },
      { path: '/u/:userId', element: <Profile /> },
      { path: '/requests', element: <Requests /> },
      { path: '/contacts', element: <Contacts /> },
      { path: '/settings', element: <Settings /> },
      { path: '/settings/encryption', element: <EncryptionInfo /> },
    ],
  },
  // Guest shared ephemeral link (no auth, no shell).
  { path: '/room/:code', element: <StandaloneRoom /> },
  { path: '*', element: <Navigate to="/" replace /> },
]);

export default function App() {
  const bootstrap = useAuth((s) => s.bootstrap);
  useEffect(() => {
    bootstrap();
  }, [bootstrap]);
  return <RouterProvider router={router} />;
}
