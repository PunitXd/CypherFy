import { useEffect, useState } from 'react';
import { Outlet } from 'react-router-dom';
import Sidebar from '../components/shell/Sidebar';
import DetailsPanel from '../components/shell/DetailsPanel';
import { ShellContext } from '../shell/ShellContext';
import { socketService } from '../socket/socket';
import { callController } from '../call/CallController';
import { useRealtime } from '../store/realtime';

// The post-login 3-column shell. Owns the single persistent socket that powers
// live presence, DM-list updates, the requests badge, and incoming calls.
export default function AppShell() {
  const [detailsOpen, setDetailsOpen] = useState(false);
  const [active, setActive] = useState(null); // conversation metadata from ChatPane

  useEffect(() => {
    const rt = useRealtime.getState();
    socketService.ensure();

    const onOnline = (d) => rt.setOnline(d.userId, d.isOnline, d.lastSeenAt);
    const onDm = (d) => {
      rt.bumpDm();
      // A DM arrived while we're not inside it → our device has it: mark delivered.
      if (d?.roomId) socketService.emit('message_seen', { roomId: d.roomId, state: 'delivered' });
    };
    const onReq = () => rt.incRequests();
    const onReqAccepted = () => rt.bumpDm();
    socketService.on('online_status', onOnline);
    socketService.on('dm_activity', onDm);
    socketService.on('chat_request', onReq);
    socketService.on('request_accepted', onReqAccepted);

    // Announce presence + (re)wire call signalling on connect and reconnect.
    const announce = () => {
      socketService.emit('update_online', { isOnline: true });
      callController.registerSignaling();
    };
    if (socketService.connected) announce();
    socketService.onConnect(announce);

    return () => {
      socketService.off('online_status', onOnline);
      socketService.off('dm_activity', onDm);
      socketService.off('chat_request', onReq);
      socketService.off('request_accepted', onReqAccepted);
      socketService.off('connect', announce);
      // The socket is closed on logout (auth store), not on shell unmount, so it
      // survives transient re-renders and route changes.
    };
  }, []);

  return (
    <ShellContext.Provider value={{ detailsOpen, setDetailsOpen, active, setActive }}>
      <div className="cipher shell">
        <Sidebar />
        <main className="shell-main">
          <Outlet />
        </main>
        {detailsOpen && active && <DetailsPanel />}
      </div>
    </ShellContext.Provider>
  );
}
