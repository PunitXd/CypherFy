import { useEffect, useMemo, useRef, useState } from 'react';
import { useParams, useLocation, useNavigate } from 'react-router-dom';
import { Paperclip, Send, Phone, Video, Info, Lock, Hash, Users, Clock } from 'lucide-react';
import { useChat } from '../chat/useChat';
import { roomApi } from '../api/rooms';
import { errMsg } from '../api/client';
import { generateAlias } from '../utils/alias';
import { useAuth } from '../store/auth';
import { useShell } from '../shell/ShellContext';
import { callController } from '../call/CallController';
import { useCall } from '../call/useCall';
import MessageBubble from '../components/chat/MessageBubble';
import Avatar from '../components/Avatar';
import CallOverlay from '../components/call/CallOverlay';

// Resolver: derive room-key inputs, then mount the live chat column.
export default function ChatPane({ ephemeral, standalone }) {
  const params = useParams();
  const loc = useLocation();
  const user = useAuth((s) => s.user);

  const code = ephemeral ? (params.code || '').toUpperCase() : null;
  const roomId = ephemeral ? null : params.roomId;

  const [opts, setOpts] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (ephemeral) {
        const alias = loc.state?.alias || generateAlias();
        const isHost = loc.state?.isHost ?? false;
        let isLocked = loc.state?.isLocked;
        let roomName = loc.state?.roomName;
        if (isLocked === undefined) {
          try {
            const info = await roomApi.validateCode(code);
            isLocked = info.isLocked;
            roomName = info.name;
          } catch (e) {
            if (!cancelled) setError(errMsg(e, 'Room not found or expired'));
            return;
          }
        }
        if (!cancelled) setOpts({ isEphemeral: true, code, myAlias: alias, isHost, isLocked: !!isLocked, roomName, standalone: !!standalone });
      } else {
        // The permanent room's own name is the generic "Direct Message"; the
        // header should show the OTHER participant. Prefer what the sidebar/profile
        // passed; on a cold load (refresh) resolve it from the DM list.
        let roomName = loc.state?.roomName;
        let otherUserId = loc.state?.otherUserId;
        if (!roomName) {
          try {
            const rooms = await roomApi.getPermanentRooms();
            const r = rooms.find((x) => String(x.roomId) === String(roomId));
            if (r) {
              roomName = r.other?.displayName || r.name;
              otherUserId = r.other?._id;
            }
          } catch {
            /* ignore */
          }
        }
        if (!cancelled) {
          setOpts({
            isEphemeral: false,
            roomId,
            myAlias: user?.displayName || 'You',
            myUserId: user?._id,
            roomName,
            otherUserId,
          });
        }
      }
    })();
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [code, roomId]);

  if (error) return <div className="chat-empty">{error}</div>;
  if (!opts) return <div className="chat-empty"><div className="spinner" /></div>;
  return <ChatInner opts={opts} key={opts.code || opts.roomId} />;
}

function ChatInner({ opts }) {
  const nav = useNavigate();
  const shell = useShell();
  const call = useCall();
  const [state, ctrl] = useChat(opts);
  const [text, setText] = useState('');
  const [secondsLeft, setSecondsLeft] = useState(null);
  const scrollRef = useRef(null);
  const fileRef = useRef(null);
  const isRoom = opts.isEphemeral;

  // For rooms the room's own name is meaningful; for DMs it's the generic
  // "Direct Message", so prefer the resolved peer name and ignore that default.
  const title = isRoom
    ? state.roomName || opts.roomName || opts.code
    : opts.roomName ||
      (state.roomName && state.roomName !== 'Direct Message' ? state.roomName : null) ||
      'Direct message';

  // Live TTL countdown (ephemeral rooms).
  useEffect(() => {
    if (!state.expiresAt) return;
    const end = new Date(state.expiresAt).getTime();
    const tick = () => setSecondsLeft(Math.max(0, Math.round((end - Date.now()) / 1000)));
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [state.expiresAt]);

  const ttl = useMemo(() => {
    if (secondsLeft == null) return null;
    const h = Math.floor(secondsLeft / 3600);
    const m = Math.floor((secondsLeft % 3600) / 60);
    const s = secondsLeft % 60;
    return h > 0 ? `${h}h ${m}m` : m > 0 ? `${m}m ${s}s` : `${s}s`;
  }, [secondsLeft]);
  const ttlUrgent = secondsLeft != null && secondsLeft <= 60;

  // Publish active-conversation metadata to the shell (for the Details panel).
  useEffect(() => {
    if (!shell) return;
    shell.setActive({
      title, roomId: opts.roomId, code: opts.code, isEphemeral: isRoom,
      otherUserId: opts.otherUserId, online: !isRoom && state.members.length > 1,
      isHost: opts.isHost, members: state.members, expiresAt: state.expiresAt,
      onEnd: () => ctrl.endRoom(),
    });
    return () => { shell.setActive(null); shell.setDetailsOpen(false); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [title, opts.roomId, opts.code, state.members, state.expiresAt]);

  useEffect(() => {
    const onVis = () => ctrl.setForeground(document.visibilityState === 'visible');
    document.addEventListener('visibilitychange', onVis);
    return () => document.removeEventListener('visibilitychange', onVis);
  }, [ctrl]);

  useEffect(() => { if (state.connected) callController.registerSignaling(); }, [state.connected]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' });
  }, [state.messages.length, state.typingAliases.length]);

  function submit(e) {
    e.preventDefault();
    if (!text.trim()) return;
    ctrl.sendText(text);
    setText('');
  }
  function onType(e) { setText(e.target.value); ctrl.handleTyping(e.target.value.length > 0); }
  async function onPickFile(e) {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    const bytes = new Uint8Array(await file.arrayBuffer());
    try { await ctrl.sendFileBytes(bytes, file.name, file.type || 'application/octet-stream'); }
    catch { ctrl._set({ errorMessage: 'File upload failed (check R2 CORS)' }); }
  }
  async function download(m) {
    try {
      const bytes = await ctrl.fetchFileBytes(m);
      const blob = new Blob([bytes], { type: m.fileType || 'application/octet-stream' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url; a.download = m.fileName || 'file'; a.click();
      URL.revokeObjectURL(url);
    } catch { ctrl._set({ errorMessage: 'Download failed' }); }
  }
  function startCall(video) {
    callController.startCall({
      code: isRoom ? opts.code : undefined,
      roomId: isRoom ? undefined : opts.roomId,
      peerName: title, video, isGroup: isRoom,
    });
  }

  if (state.ended) return <ChatNotice title="Room ended" sub="This room and its messages have been deleted." onBack={() => nav('/app')} />;
  if (state.rejected) return <ChatNotice title="Entry declined" sub="The host didn't admit you." onBack={() => nav('/app')} />;
  if (state.waitingForAdmission) return <ChatNotice title="Knocking…" sub="Waiting for the host to let you in." spinner />;

  return (
    <div className={`chatpane ${isRoom ? 'is-room' : 'is-dm'}`}>
      <header className="cp-header">
        <div
          className={`cp-peer ${!isRoom && opts.otherUserId ? 'clickable' : ''}`}
          onClick={() => {
            if (!isRoom && opts.otherUserId) nav(`/u/${opts.otherUserId}`);
            else if (shell) shell.setDetailsOpen(true);
          }}
        >
          {isRoom ? (
            <div className="cp-room-badge"><Hash size={16} /></div>
          ) : (
            <Avatar name={title} size={34} online={state.members.length > 1} />
          )}
          <div>
            <div className="cp-name">{title}</div>
            {isRoom ? (
              <div className="cp-sub">
                <Users size={10} /> {state.members.length || 1}
                {ttl && <> · <Clock size={10} className={ttlUrgent ? 'cp-urgent' : ''} /> <span className={ttlUrgent ? 'cp-urgent' : ''}>{ttl}</span></>}
                <span className="mono cp-code"> · {opts.code}</span>
              </div>
            ) : (
              <div className="cp-sub"><Lock size={9} /> end-to-end encrypted</div>
            )}
          </div>
        </div>
        <div className="cp-actions">
          <button className="cx-icon-btn" title="Voice call" onClick={() => startCall(false)}><Phone size={15} /></button>
          <button className="cx-icon-btn" title="Video call" onClick={() => startCall(true)}><Video size={15} /></button>
          {shell && (
            <button className={`cx-icon-btn ${shell.detailsOpen ? 'active' : ''}`} title={isRoom ? 'Room info' : 'Details'} onClick={() => shell.setDetailsOpen((v) => !v)}>
              <Info size={15} />
            </button>
          )}
        </div>
      </header>

      {isRoom && state.groupCallId && call.status === 'idle' && (
        <button
          className="cp-callbanner"
          onClick={() => callController.joinGroupCall({ callId: state.groupCallId, video: state.groupCallType === 'video', peerName: title })}
        >
          <Phone size={13} /> Group {state.groupCallType === 'video' ? 'video ' : ''}call in progress · {state.groupCallCount} joined — tap to rejoin
        </button>
      )}
      {state.expiringSecondsLeft != null && (
        <div className="cp-expiry">⏳ This room expires in {state.expiringSecondsLeft}s</div>
      )}
      {state.errorMessage && (
        <div className="cp-error" onClick={() => ctrl.clearError()}>{state.errorMessage} — tap to dismiss</div>
      )}

      {state.knockRequests.length > 0 && (
        <div className="cp-knocks">
          {state.knockRequests.map((k) => (
            <div key={k.socketId} className="cp-knock">
              <span><b>{k.alias}</b> wants to join</span>
              <div>
                <button className="cx-btn" style={{ padding: '5px 12px' }} onClick={() => ctrl.admit(k.socketId)}>Admit</button>
                <button className="cx-btn ghost" style={{ padding: '5px 12px', marginLeft: 6 }} onClick={() => ctrl.reject(k.socketId)}>Reject</button>
              </div>
            </div>
          ))}
        </div>
      )}

      <div className="cp-messages" ref={scrollRef}>
        <div className="cp-daylabel mono">{isRoom ? 'ephemeral · session encrypted' : 'session encrypted'}</div>
        {state.messages.map((m) => (
          <MessageBubble
            key={m.messageId}
            m={m}
            isOwn={ctrl._isOwn(m)}
            senderName={m.senderAlias}
            showAvatar={isRoom}
            onReact={(id, e) => ctrl.react(id, e)}
            onDelete={(id) => ctrl.deleteMessage(id)}
            onDownload={download}
          />
        ))}
        {state.typingAliases.length > 0 && (
          <div className="cp-typing">
            <Avatar name={state.typingAliases[0]} size={26} />
            <div className="cp-typing-bubble">
              {[0, 1, 2].map((i) => <span key={i} className="cp-dot" style={{ animationDelay: `${i * 0.2}s` }} />)}
            </div>
          </div>
        )}
      </div>

      <div className="cp-composer-wrap">
        <div className="cp-composer">
          <button type="button" className="cp-attach" onClick={() => fileRef.current?.click()} title="Attach"><Paperclip size={16} /></button>
          <input ref={fileRef} type="file" hidden onChange={onPickFile} />
          <textarea
            className="cp-input"
            placeholder="Message…"
            rows={1}
            value={text}
            onChange={onType}
            onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submit(e); } }}
            onBlur={() => ctrl.stopTyping()}
          />
          <span className="cp-cipher mono">AES-256</span>
          <button className="cp-send" disabled={!text.trim()} onClick={submit} title="Send"><Send size={14} /></button>
        </div>
      </div>

      <CallOverlay />
    </div>
  );
}

function ChatNotice({ title, sub, onBack, spinner }) {
  return (
    <div className="chat-empty">
      {spinner && <div className="spinner" />}
      <h2>{title}</h2>
      <p className="cx-muted">{sub}</p>
      {onBack && <button className="cx-btn ghost" style={{ marginTop: 12 }} onClick={onBack}>Back</button>}
    </div>
  );
}
