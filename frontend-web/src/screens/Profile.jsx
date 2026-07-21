import { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { userApi } from '../api/users';
import { errMsg } from '../api/client';
import Page from '../components/Page';
import Avatar from '../components/Avatar';
import Notice from '../components/Notice';

export default function Profile() {
  const { userId } = useParams();
  const nav = useNavigate();
  const [data, setData] = useState(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function load() {
    setError('');
    try {
      setData(await userApi.profile(userId));
    } catch (e) {
      setError(errMsg(e, 'Could not load profile'));
    }
  }
  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId]);

  async function sendRequest() {
    setBusy(true);
    setError('');
    try {
      await userApi.sendRequest(userId);
      await load();
    } catch (e) {
      setError(errMsg(e, 'Could not send request'));
    } finally {
      setBusy(false);
    }
  }

  async function accept(requestId) {
    setBusy(true);
    setError('');
    try {
      const room = await userApi.acceptRequest(requestId);
      nav(`/app/dm/${room._id}`, { state: { roomName: data.user.displayName } });
    } catch (e) {
      setError(errMsg(e, 'Could not accept request'));
      setBusy(false);
    }
  }

  if (error && !data) {
    return (
      <Page title="Profile">
        <Notice type="error">{error}</Notice>
      </Page>
    );
  }
  if (!data) {
    return (
      <Page title="Profile">
        <div className="spinner" />
      </Page>
    );
  }

  const { user, relationship: rel } = data;

  function ActionButton() {
    if (rel.isSelf) {
      return <button className="login-button" onClick={() => nav('/settings')}>Edit profile</button>;
    }
    if (rel.roomId) {
      return (
        <button className="login-button" onClick={() => nav(`/app/dm/${rel.roomId}`, { state: { roomName: user.displayName } })}>
          Message
        </button>
      );
    }
    if (rel.incomingRequestId) {
      return (
        <button className="login-button" disabled={busy} onClick={() => accept(rel.incomingRequestId)}>
          Accept request
        </button>
      );
    }
    if (rel.outgoingPending) {
      return <button className="login-button ghost" disabled>Request sent</button>;
    }
    return (
      <button className="login-button" disabled={busy} onClick={sendRequest}>
        {busy ? 'Sending…' : 'Send message request'}
      </button>
    );
  }

  return (
    <Page title="Profile">
      <div className="profile-head">
        <Avatar src={user.avatar} name={user.displayName} size={88} />
        <h2>{user.displayName}</h2>
        <span className="muted">@{user.username}</span>
        {user.bio && <p className="profile-bio">{user.bio}</p>}
        <span className="muted">
          {user.isOnline ? '● Online' : user.lastSeenAt ? `Last seen ${new Date(user.lastSeenAt).toLocaleString()}` : ''}
        </span>
      </div>
      <Notice type="error">{error}</Notice>
      <ActionButton />
      {!rel.isSelf && <MuteCard userId={userId} rel={rel} />}
    </Page>
  );
}

const INDEFINITE = 253370764800000; // year ~9999 → "until turned off"
const MUTE_OPTIONS = [
  ['For 15 minutes', () => Date.now() + 15 * 60000],
  ['For 1 hour', () => Date.now() + 3600000],
  ['For 8 hours', () => Date.now() + 8 * 3600000],
  ['For 1 day', () => Date.now() + 86400000],
  ['Until I turn it back on', () => INDEFINITE],
];

function muteLabel(until) {
  if (!until) return 'Off';
  const d = new Date(until);
  if (d.getTime() < Date.now()) return 'Off';
  if (d.getFullYear() >= 9000) return 'Until you turn it back on';
  return `Until ${d.toLocaleString([], { hour: '2-digit', minute: '2-digit' })}`;
}

function MuteCard({ userId, rel }) {
  const [msg, setMsg] = useState(rel.messagesMutedUntil);
  const [call, setCall] = useState(rel.callsMutedUntil);
  const [open, setOpen] = useState(null); // 'messages' | 'calls'

  async function apply(scope, until) {
    setOpen(null);
    const body = scope === 'messages' ? { messagesUntil: until } : { callsUntil: until };
    try {
      await userApi.setMute(userId, body);
      if (scope === 'messages') setMsg(until);
      else setCall(until);
    } catch {
      /* ignore */
    }
  }

  return (
    <div className="settings-card">
      <h3>Notifications</h3>
      <button className="mute-row" onClick={() => setOpen('messages')}>
        <span>Mute messages</span>
        <span className="cx-dim">{muteLabel(msg)} ›</span>
      </button>
      <button className="mute-row" onClick={() => setOpen('calls')}>
        <span>Mute calls</span>
        <span className="cx-dim">{muteLabel(call)} ›</span>
      </button>

      {open && (
        <div className="modal-scrim" onClick={() => setOpen(null)}>
          <div className="modal cx-card" onClick={(e) => e.stopPropagation()}>
            <div className="modal-head">
              <span style={{ fontWeight: 600 }}>{open === 'calls' ? 'Mute calls' : 'Mute messages'}</span>
            </div>
            <div className="mute-menu">
              {MUTE_OPTIONS.map(([label, val]) => (
                <button key={label} onClick={() => apply(open, val())}>{label}</button>
              ))}
              <button className="unmute" onClick={() => apply(open, null)}>Unmute</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
