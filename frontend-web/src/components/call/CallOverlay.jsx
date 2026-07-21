import { useEffect, useState } from 'react';
import { Phone, PhoneOff, Mic, MicOff, Video, VideoOff, Minimize2 } from 'lucide-react';
import { useCall } from '../../call/useCall';
import { callController } from '../../call/CallController';
import VideoTile from './VideoTile';

function useTimer(startedAt) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    if (!startedAt) return;
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [startedAt]);
  if (!startedAt) return '';
  const s = Math.max(0, Math.floor((now - startedAt) / 1000));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

// Rendered globally inside a chat room. Draws whatever the call state requires.
export default function CallOverlay() {
  const c = useCall();
  const timer = useTimer(c.startedAt);

  if (c.status === 'idle') return null;

  // Ended note (brief).
  if (c.status === 'ended') {
    return (
      <div className="call-scrim">
        <div className="call-ended">{c.note || 'Call ended'}</div>
      </div>
    );
  }

  // Incoming ring.
  if (c.status === 'incoming') {
    return (
      <div className="call-scrim ring">
        <div className="ring-card">
          <div className="ring-avatar">{(c.peerName || '?').charAt(0).toUpperCase()}</div>
          <h2>{c.peerName || 'Incoming call'}</h2>
          <p className="muted">Incoming {c.callType} call…</p>
          <div className="ring-actions">
            <button className="call-btn decline" onClick={() => callController.reject()}>
              <PhoneOff size={22} />
            </button>
            <button className="call-btn accept" onClick={() => callController.acceptIncoming()}>
              <Phone size={22} />
            </button>
          </div>
        </div>
      </div>
    );
  }

  // Minimized → small banner.
  if (c.minimized) {
    return (
      <button className="call-mini" onClick={() => callController.returnToCall()}>
        ● In call {timer && `· ${timer}`} — tap to return
      </button>
    );
  }

  // Active call screen (outgoing / connecting / connected).
  const statusLine =
    c.status === 'outgoing' ? 'Ringing…' : c.status === 'connecting' ? 'Connecting…' : timer;

  return (
    <div className="call-scrim active">
      <div className="call-screen">
        <div className="call-top">
          <span className="call-peer">{c.peerName || (c.isGroup ? 'Group call' : 'Call')}</span>
          <span className="call-status">{statusLine}</span>
          <button className="icon-btn" onClick={() => callController.minimize()} title="Minimize">
            <Minimize2 size={18} />
          </button>
        </div>

        {c.flash && <div className="call-flash">{c.flash}</div>}

        <div className={`video-grid n${c.participants.length + 1}`}>
          <VideoTile
            stream={c.localStream}
            muted
            mirror
            label="You"
            hasVideo={c.callType === 'video' && c.camOn}
          />
          {c.participants.map((p) => (
            <VideoTile
              key={p.socketId}
              stream={p.stream}
              label={p.name}
              hasVideo={p.hasVideo}
            />
          ))}
        </div>

        <div className="call-controls">
          <button className={`call-btn ${c.micOn ? '' : 'off'}`} onClick={() => callController.toggleMute()}>
            {c.micOn ? <Mic size={20} /> : <MicOff size={20} />}
          </button>
          {c.callType === 'video' && (
            <button className={`call-btn ${c.camOn ? '' : 'off'}`} onClick={() => callController.toggleCamera()}>
              {c.camOn ? <Video size={20} /> : <VideoOff size={20} />}
            </button>
          )}
          <button
            className="call-btn decline"
            onClick={() => (c.status === 'outgoing' ? callController.cancel() : callController.hangUp())}
          >
            <PhoneOff size={20} />
          </button>
        </div>
      </div>

      {/* Call-waiting card during an active call. */}
      {c.waiting && (
        <div className="waiting-card">
          <span>
            <b>{c.waiting.name}</b> is calling ({c.waiting.callType})
          </span>
          <div>
            <button className="mini" onClick={() => callController.acceptWaiting()}>Accept</button>
            <button className="mini ghost" onClick={() => callController.declineWaiting()}>Decline</button>
          </div>
        </div>
      )}
    </div>
  );
}
