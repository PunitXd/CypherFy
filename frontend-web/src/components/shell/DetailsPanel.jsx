import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { X, Hash, Copy, Check } from 'lucide-react';
import { useShell } from '../../shell/ShellContext';
import { roomApi } from '../../api/rooms';
import Avatar from '../Avatar';

const ENCRYPTION = [
  ['Cipher', 'AES-256-GCM'],
  ['Key derivation', 'PBKDF2 · SHA-256'],
  ['Iterations', '100,000'],
  ['Calls', 'DTLS-SRTP'],
  ['Zero-knowledge', '✓'],
];

function expiryLabel(expiresAt) {
  if (!expiresAt) return null;
  const d = new Date(expiresAt).getTime() - Date.now();
  if (d <= 0) return 'Expired';
  const h = Math.floor(d / 3600000);
  if (h >= 24) return `Expires in ${Math.floor(h / 24)}d`;
  if (h >= 1) return `Expires in ${h}h`;
  return `Expires in ${Math.floor(d / 60000)}m`;
}

function EncryptionCard() {
  return (
    <div className="details-section">
      <div className="cx-section">Encryption</div>
      <div className="cx-card details-table">
        {ENCRYPTION.map(([k, v], i) => (
          <div className="details-row" key={k} style={{ borderBottom: i < ENCRYPTION.length - 1 ? '1px solid var(--divider)' : 'none' }}>
            <span className="cx-muted">{k}</span>
            <span className="mono" style={{ color: v === '✓' ? 'var(--green)' : 'var(--t1)', fontSize: 11.5 }}>{v}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

export default function DetailsPanel() {
  const nav = useNavigate();
  const { active, setDetailsOpen } = useShell();
  const [copied, setCopied] = useState(false);

  const isRoom = active.isEphemeral;

  async function copyCode() {
    try {
      await navigator.clipboard.writeText(active.code);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      /* ignore */
    }
  }
  async function del() {
    if (!isRoom && active.roomId) {
      try { await roomApi.deletePermanent(active.roomId); } catch { /* ignore */ }
    }
    nav('/app');
  }
  function endRoom() {
    active.onEnd?.();
    nav('/app');
  }

  const header = (
    <div className="details-head">
      <span>{isRoom ? 'Room info' : 'Details'}</span>
      <button className="cx-icon-btn" onClick={() => setDetailsOpen(false)}><X size={14} /></button>
    </div>
  );

  // ── Ephemeral room ──────────────────────────────────────
  if (isRoom) {
    const exp = expiryLabel(active.expiresAt);
    return (
      <aside className="details" style={{ animation: 'cx-rise 0.18s ease-out' }}>
        {header}
        <div className="details-id">
          <div className="cp-room-badge lg"><Hash size={26} /></div>
          <div className="details-name">{active.title}</div>
          <div className="cx-dim">Ephemeral room</div>
        </div>

        {/* Room code card */}
        <div className="details-section">
          <div className="cx-section">Room code</div>
          <div className="cx-card code-card">
            <div className="code-value mono">{active.code}</div>
            {exp && <div className="code-expiry mono">{exp.toUpperCase()}</div>}
            <button className="cx-btn ghost code-copy" onClick={copyCode}>
              {copied ? <Check size={14} /> : <Copy size={14} />} {copied ? 'Copied' : 'Copy code'}
            </button>
          </div>
          <div className="code-hint cx-dim">Anyone with this code can join.</div>
        </div>

        {/* Members */}
        <div className="details-section">
          <div className="cx-section">In the room · {active.members?.length || 0}</div>
          <div className="cx-card">
            {(active.members || []).map((m, i) => (
              <div className="details-row" key={m.socketId || m.alias || i} style={{ borderBottom: i < (active.members.length - 1) ? '1px solid var(--divider)' : 'none' }}>
                <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <Avatar name={m.alias} size={22} /> <span style={{ fontSize: 13 }}>{m.alias}</span>
                </span>
              </div>
            ))}
            {(!active.members || active.members.length === 0) && (
              <div className="details-row"><span className="cx-dim" style={{ fontSize: 12 }}>Just you so far</span></div>
            )}
          </div>
        </div>

        <EncryptionCard />

        <div className="details-actions">
          {active.isHost && <button className="details-action danger" onClick={endRoom}>End room for everyone</button>}
          <button className="details-action" onClick={() => nav('/app')}>Leave room</button>
        </div>
      </aside>
    );
  }

  // ── Permanent DM ────────────────────────────────────────
  return (
    <aside className="details" style={{ animation: 'cx-rise 0.18s ease-out' }}>
      {header}
      <div className="details-id">
        <Avatar name={active.title} size={60} online={active.online} />
        <div className="details-name">{active.title}</div>
        <div className="cx-dim">{active.online ? 'Online' : 'Offline'}</div>
      </div>
      <EncryptionCard />
      <div className="details-actions">
        {active.otherUserId && (
          <button className="details-action" onClick={() => { setDetailsOpen(false); nav(`/u/${active.otherUserId}`); }}>
            Notifications & mute
          </button>
        )}
        <button className="details-action danger" onClick={del}>Delete conversation</button>
      </div>
    </aside>
  );
}
