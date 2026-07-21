// Minimal WebAudio ringer for incoming calls (no audio asset needed). Best-effort
// — browser autoplay policy may suspend it until a user gesture, which is fine
// since the user is already interacting with the app.

let ctx = null;
let timer = null;

function tone(freq = 440, dur = 0.6) {
  if (!ctx) return;
  const o = ctx.createOscillator();
  const g = ctx.createGain();
  o.frequency.value = freq;
  o.connect(g);
  g.connect(ctx.destination);
  const t = ctx.currentTime;
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(0.12, t + 0.05);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.start(t);
  o.stop(t + dur + 0.02);
}

export function ringStart() {
  ringStop();
  try {
    ctx = new (window.AudioContext || window.webkitAudioContext)();
    const ring = () => {
      tone(480, 0.4);
      setTimeout(() => tone(440, 0.4), 500);
    };
    ring();
    timer = setInterval(ring, 2500);
  } catch {
    /* audio unavailable */
  }
}

export function ringStop() {
  if (timer) clearInterval(timer);
  timer = null;
  try {
    ctx?.close();
  } catch {
    /* ignore */
  }
  ctx = null;
}

// Short one-shot alert for call-waiting (already on a call).
export function beepOnce() {
  try {
    const c = new (window.AudioContext || window.webkitAudioContext)();
    const o = c.createOscillator();
    const g = c.createGain();
    o.frequency.value = 660;
    o.connect(g);
    g.connect(c.destination);
    g.gain.setValueAtTime(0.12, c.currentTime);
    g.gain.exponentialRampToValueAtTime(0.0001, c.currentTime + 0.25);
    o.start();
    o.stop(c.currentTime + 0.27);
    setTimeout(() => c.close(), 400);
  } catch {
    /* ignore */
  }
}
