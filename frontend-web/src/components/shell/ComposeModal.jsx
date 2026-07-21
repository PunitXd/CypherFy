import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { X } from 'lucide-react';
import { roomApi } from '../../api/rooms';
import { errMsg } from '../../api/client';
import { generateAlias } from '../../utils/alias';

const TTL_OPTIONS = [
  { label: '1 hour', value: 3600 },
  { label: '6 hours', value: 21600 },
  { label: '24 hours', value: 86400 },
  { label: '7 days', value: 604800 },
];

export default function ComposeModal({ onClose, initialMode }) {
  const nav = useNavigate();
  const [mode, setMode] = useState(initialMode || 'create');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const [name, setName] = useState('Cypher Room');
  const [maxUsers, setMaxUsers] = useState(2);
  const [ttlSeconds, setTtl] = useState(3600);
  const [isLocked, setLocked] = useState(false);
  const [code, setCode] = useState('');

  async function create(e) {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      const alias = generateAlias();
      const room = await roomApi.createEphemeral({ alias, name, maxUsers, ttlSeconds, isLocked });
      onClose();
      nav(`/app/room/${room.code}`, { state: { alias, isHost: true, isLocked, roomName: room.name } });
    } catch (err) {
      setError(errMsg(err, 'Could not create room'));
      setBusy(false);
    }
  }

  async function join(e) {
    e.preventDefault();
    const c = code.trim().toUpperCase();
    if (!c) return;
    setBusy(true);
    setError('');
    try {
      const info = await roomApi.validateCode(c);
      const alias = generateAlias();
      onClose();
      nav(`/app/room/${c}`, { state: { alias, isHost: false, isLocked: info.isLocked, roomName: info.name } });
    } catch (err) {
      setError(errMsg(err, 'Room not found or expired'));
      setBusy(false);
    }
  }

  return (
    <div className="modal-scrim" onClick={onClose}>
      <div className="modal cx-card" onClick={(e) => e.stopPropagation()}>
        <div className="modal-head">
          <div className="modal-tabs">
            <button className={mode === 'create' ? 'on' : ''} onClick={() => setMode('create')}>New room</button>
            <button className={mode === 'join' ? 'on' : ''} onClick={() => setMode('join')}>Join by code</button>
          </div>
          <button className="cx-icon-btn" onClick={onClose}><X size={14} /></button>
        </div>

        {error && <div className="notice error">{error}</div>}

        {mode === 'create' ? (
          <form className="modal-body" onSubmit={create}>
            <input className="login-input" placeholder="Room name" value={name} onChange={(e) => setName(e.target.value)} />
            <div className="modal-row">
              <label className="field">Max users
                <select className="login-input" value={maxUsers} onChange={(e) => setMaxUsers(Number(e.target.value))}>
                  {[2, 3, 4, 5, 6, 8, 10].map((n) => <option key={n} value={n}>{n}</option>)}
                </select>
              </label>
              <label className="field">Auto-delete
                <select className="login-input" value={ttlSeconds} onChange={(e) => setTtl(Number(e.target.value))}>
                  {TTL_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
                </select>
              </label>
            </div>
            <label className="toggle-row">
              <span>Locked (guests must knock)</span>
              <input type="checkbox" checked={isLocked} onChange={(e) => setLocked(e.target.checked)} />
            </label>
            <button className="login-button" disabled={busy}>{busy ? 'Creating…' : 'Create & enter'}</button>
          </form>
        ) : (
          <form className="modal-body" onSubmit={join}>
            <input className="login-input mono" placeholder="6-char code" maxLength={6} value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} />
            <button className="login-button" disabled={busy}>{busy ? 'Joining…' : 'Join room'}</button>
          </form>
        )}
      </div>
    </div>
  );
}
