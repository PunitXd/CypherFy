// Cipher-style avatar: image if present, else initials on a deterministic
// per-name HSL background, with an optional green online dot.

import { useState, useEffect } from 'react';

function initials(name) {
  return (name || '?')
    .trim()
    .split(/\s+/)
    .map((w) => w[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();
}

function hueOf(name) {
  let h = 0;
  const s = name || '';
  for (let i = 0; i < s.length; i += 1) h = (h * 31 + s.charCodeAt(i)) & 0xffff;
  return h % 360;
}

export default function Avatar({ src, name, size = 36, online }) {
  const h = hueOf(name || '');
  const [failed, setFailed] = useState(false);

  // Reset the error state when the image source changes.
  useEffect(() => setFailed(false), [src]);

  const showImg = src && !failed;

  return (
    <div style={{ position: 'relative', width: size, height: size, flexShrink: 0 }}>
      {showImg ? (
        <img
          src={src}
          alt={name || ''}
          onError={() => setFailed(true)}
          style={{ width: size, height: size, borderRadius: '50%', objectFit: 'cover' }}
        />
      ) : (
        <div
          style={{
            width: size,
            height: size,
            borderRadius: '50%',
            background: `hsl(${h},22%,24%)`,
            border: `1px solid hsl(${h},20%,32%)`,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontSize: size * 0.31,
            fontWeight: 500,
            color: `hsl(${h},50%,75%)`,
            letterSpacing: '0.02em',
          }}
        >
          {initials(name)}
        </div>
      )}
      {online && (
        <div
          style={{
            position: 'absolute',
            bottom: 0,
            right: 0,
            width: Math.max(8, size * 0.24),
            height: Math.max(8, size * 0.24),
            borderRadius: '50%',
            background: 'var(--green)',
            border: '1.5px solid var(--panel)',
          }}
        />
      )}
    </div>
  );
}
