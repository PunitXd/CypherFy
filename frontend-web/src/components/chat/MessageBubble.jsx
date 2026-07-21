import { useState } from 'react';
import { Download, Trash2, Smile } from 'lucide-react';
import Avatar from '../Avatar';

const REACTIONS = ['👍', '❤️', '😂', '🔥'];

function fmtTime(iso) {
  return new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}
function fmtSize(bytes) {
  if (!bytes) return '';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

function Ticks({ m }) {
  const read = m.readBy.length > 0;
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke={read ? 'var(--green)' : 'var(--t3)'} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="17 6 9 17 4 12" />
      <path d="M21 6l-8 11" />
    </svg>
  );
}

export default function MessageBubble({ m, isOwn, senderName, showAvatar, onReact, onDelete, onDownload }) {
  const isFile = m.type === 'file';
  const [pick, setPick] = useState(false);
  return (
    <div className={`mb-row ${isOwn ? 'own' : ''}`}>
      {!isOwn && (showAvatar ? <Avatar name={senderName} size={26} /> : <div style={{ width: 26 }} />)}
      <div className="mb-col">
        {!isOwn && showAvatar && <span className="mb-sender">{senderName}</span>}
        <div className="mb-bubble-wrap" onMouseLeave={() => setPick(false)}>
          {isFile ? (
            <button className={`mb-file ${isOwn ? 'own' : ''}`} onClick={() => onDownload(m)} title="Download & decrypt">
              <Download size={15} />
              <span className="mb-file-name">{m.fileName || 'file'}</span>
              <span className="mb-file-size">{fmtSize(m.size)}</span>
            </button>
          ) : (
            <div className={`mb-bubble ${isOwn ? 'own' : ''}`}>{m.decryptedText}</div>
          )}
          <div className="mb-tools">
            {pick ? (
              <div className="mb-emoji">
                {REACTIONS.map((e) => (
                  <button key={e} onClick={() => { onReact(m.messageId, e); setPick(false); }}>{e}</button>
                ))}
              </div>
            ) : (
              <>
                <button title="React" onClick={() => setPick(true)}><Smile size={13} /></button>
                {isOwn && <button title="Delete" onClick={() => onDelete(m.messageId)}><Trash2 size={13} /></button>}
              </>
            )}
          </div>
        </div>
        {Object.keys(m.reactions || {}).length > 0 && (
          <div className="mb-reactions">
            {Object.entries(m.reactions).map(([e, c]) => (
              <span key={e} className="mb-reaction">{e} {c}</span>
            ))}
          </div>
        )}
        <div className="mb-meta">
          <span className="mono">{fmtTime(m.createdAt)}</span>
          {isOwn && <Ticks m={m} />}
        </div>
      </div>
    </div>
  );
}
