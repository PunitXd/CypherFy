import { useEffect, useRef } from 'react';

// Binds a MediaStream to a <video>. Local tile is muted (avoid echo) + mirrored.
export default function VideoTile({ stream, muted = false, mirror = false, label, hasVideo = true }) {
  const ref = useRef(null);
  useEffect(() => {
    if (ref.current) ref.current.srcObject = stream || null;
  }, [stream]);

  const initial = (label || '?').trim().charAt(0).toUpperCase();

  return (
    <div className="video-tile">
      <video
        ref={ref}
        autoPlay
        playsInline
        muted={muted}
        className={mirror ? 'mirror' : ''}
        style={{ display: hasVideo ? 'block' : 'none' }}
      />
      {!hasVideo && (
        <div className="tile-avatar">
          <span>{initial}</span>
        </div>
      )}
      {label && <span className="tile-label">{label}</span>}
    </div>
  );
}
