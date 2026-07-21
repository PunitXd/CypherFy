import { useEffect, useRef, useState } from 'react';
import { useNavigate, useLocation, useParams } from 'react-router-dom';
import { Lock, Plus, Search, Bell, Users, Settings as SettingsIcon, LogIn, Hash } from 'lucide-react';
import { useAuth } from '../../store/auth';
import { roomApi } from '../../api/rooms';
import { userApi } from '../../api/users';
import { generateAlias } from '../../utils/alias';
import { useRealtime } from '../../store/realtime';
import Avatar from '../Avatar';
import ComposeModal from './ComposeModal';

export default function Sidebar() {
  const nav = useNavigate();
  const loc = useLocation();
  const params = useParams();
  const user = useAuth((s) => s.user);

  const [dms, setDms] = useState([]);
  const onlineUsers = useRealtime((s) => s.onlineUsers);
  const dmTick = useRealtime((s) => s.dmTick);
  const requestsCount = useRealtime((s) => s.requestsCount);
  const [query, setQuery] = useState('');
  const [results, setResults] = useState([]);
  const [composeMode, setComposeMode] = useState(null);
  const debounce = useRef(null);

  useEffect(() => {
    roomApi.getPermanentRooms().then(setDms).catch(() => {});
    userApi.getRequests().then((r) => useRealtime.getState().setRequests(r.incoming.length)).catch(() => {});
  }, [loc.pathname, dmTick]);

  useEffect(() => {
    clearTimeout(debounce.current);
    const q = query.trim();
    if (!q) {
      setResults([]);
      return;
    }
    debounce.current = setTimeout(() => {
      userApi.search(q).then(setResults).catch(() => setResults([]));
    }, 300);
    return () => clearTimeout(debounce.current);
  }, [query]);

  const activeRoomId = params.roomId;

  return (
    <aside className="sb">
      {/* Brand */}
      <div className="sb-top">
        <button
          type="button"
          className="sb-brand"
          onClick={() => nav('/app')}
          title="Home"
        >
          <div className="sb-logo"><Lock size={13} /></div>
          <span>CypherFy</span>
        </button>
        <button className="cx-icon-btn" title="New room" onClick={() => setComposeMode('create')}>
          <Plus size={16} />
        </button>
      </div>

      {/* Search */}
      <div className="sb-search-wrap">
        <div className="sb-search">
          <span className="cx-dim"><Search size={14} /></span>
          <input
            type="search"
            name="people-search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Find people by @username"
            autoComplete="off"
            autoCorrect="off"
            autoCapitalize="off"
            spellCheck={false}
            data-1p-ignore
            data-lpignore="true"
          />
        </div>
      </div>

      {/* Nav */}
      <div className="sb-nav">
        <button className="cx-icon-btn" title="Requests" onClick={() => nav('/requests')}>
          <Bell size={16} />
          {requestsCount > 0 && <span className="sb-badge">{requestsCount}</span>}
        </button>
        <button className="cx-icon-btn" title="Contacts" onClick={() => nav('/contacts')}>
          <Users size={16} />
        </button>
        <button className="cx-icon-btn" title="Settings" onClick={() => nav('/settings')}>
          <SettingsIcon size={16} />
        </button>
      </div>

      {query.trim() ? (
        <>
          <div className="cx-section sb-label">People</div>
          <div className="sb-list">
            {results.length === 0 && <div className="sb-empty">No users found.</div>}
            {results.map((u) => (
              <button key={u._id} className="sb-row" onClick={() => nav(`/u/${u._id}`)}>
                <Avatar name={u.displayName} size={36} online={u.isOnline} />
                <div className="sb-row-body">
                  <div className="sb-row-title">{u.displayName}</div>
                  <div className="sb-row-sub">@{u.username}</div>
                </div>
              </button>
            ))}
          </div>
        </>
      ) : (
        <>
          <div className="cx-section sb-label">Rooms</div>
          <div className="sb-rooms">
            <button className="sb-room-btn" onClick={() => setComposeMode('create')}>
              <span className="sb-room-ic"><Hash size={15} /></span> New room
            </button>
            <button className="sb-room-btn" onClick={() => setComposeMode('join')}>
              <span className="sb-room-ic"><LogIn size={15} /></span> Join
            </button>
          </div>
          <div className="cx-section sb-label">Messages</div>
          <div className="sb-list">
            {dms.length === 0 && <div className="sb-empty">No conversations yet.</div>}
            {dms.map((d) => {
              const name = d.other?.displayName || d.name;
              const isActive = String(activeRoomId) === String(d.roomId);
              return (
                <button
                  key={d.roomId}
                  className={`sb-row ${isActive ? 'active' : ''}`}
                  onClick={() => nav(`/app/dm/${d.roomId}`, { state: { roomName: name, otherUserId: d.other?._id } })}
                >
                  <Avatar name={name} size={36} online={onlineUsers[String(d.other?._id)]?.isOnline ?? d.other?.isOnline} />
                  <div className="sb-row-body">
                    <div className="sb-row-line">
                      <span className="sb-row-title">{name}</span>
                      <span className="sb-row-time">
                        {d.lastMessageAt ? new Date(d.lastMessageAt).toLocaleDateString([], { month: 'short', day: 'numeric' }) : ''}
                      </span>
                    </div>
                    <div className="sb-row-sub">{d.lastMessagePreview || `@${d.other?.username || ''}`}</div>
                  </div>
                </button>
              );
            })}
          </div>
        </>
      )}

      {/* Self footer */}
      <button className="sb-self" onClick={() => nav('/settings')}>
        <Avatar name={user?.displayName} src={user?.avatar} size={30} online />
        <div className="sb-self-body">
          <div className="sb-self-name">{user?.displayName || 'You'}</div>
          <div className="sb-self-sub cx-green">● Encrypted</div>
        </div>
      </button>

      {composeMode && <ComposeModal initialMode={composeMode} onClose={() => setComposeMode(null)} />}
    </aside>
  );
}
