// Call SIGNALLING end-to-end verification against the live backend.
// The media (RTCPeerConnection) is browser-native; here we prove the server
// state machine + SDP/ICE relay contract that CallController relies on.
// Run: node verify-call.mjs
import { io } from 'socket.io-client';

const BASE = 'http://localhost:8000';
const API = BASE + '/api/v1';
const connect = () => io(BASE, { transports: ['websocket'], forceNew: true });
const once = (s, ev) => new Promise((r) => s.once(ev, r));
const withTimeout = (p, ms, label) =>
  Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error('timeout: ' + label)), ms))]);

let failures = 0;
const ok = (name, cond) => {
  console.log(`  ${cond ? '✓' : '✗ FAIL'} ${name}`);
  if (!cond) failures += 1;
};

async function main() {
  // Room + two guests joined.
  const res = await fetch(API + '/rooms', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ createdBy: 'Caller', name: 'Call Room', maxUsers: 4, ttlSeconds: 3600, isLocked: false }),
  });
  const code = (await res.json()).data.code;
  console.log('Room:', code);

  const a = connect();
  const b = connect();
  await withTimeout(Promise.all([once(a, 'connect'), once(b, 'connect')]), 5000, 'connect');
  a.emit('join_room', { code, alias: 'Caller' });
  b.emit('join_room', { code, alias: 'Callee' });
  await withTimeout(Promise.all([once(a, 'room_joined'), once(b, 'room_joined')]), 5000, 'join');

  // 1. A starts a group (ephemeral) call → A gets call:started, B gets call:incoming.
  const started = once(a, 'call:started');
  const incoming = once(b, 'call:incoming');
  a.emit('call:start', { code, callType: 'audio' });
  const s = await withTimeout(started, 5000, 'call:started');
  const inc = await withTimeout(incoming, 5000, 'call:incoming');
  ok('A receives call:started with callId + iceServers', !!s.callId && Array.isArray(s.iceServers));
  ok('B receives call:incoming for same call', inc.callId === s.callId && inc.from?.name === 'Caller');
  const callId = s.callId;

  // 2. B accepts → B gets call:accepted (peers incl A), A gets call:peer_joined (B).
  const accepted = once(b, 'call:accepted');
  const peerJoined = once(a, 'call:peer_joined');
  b.emit('call:accept', { callId });
  const acc = await withTimeout(accepted, 5000, 'call:accepted');
  const pj = await withTimeout(peerJoined, 5000, 'call:peer_joined');
  const aId = acc.peers?.[0]?.socketId;
  ok('B call:accepted lists A as an existing peer', aId === a.id);
  ok('A call:peer_joined reports B', pj.socketId === b.id);

  // 3. Mesh relay: B (joiner) offers to A, A answers, B sends ICE.
  const offerOnA = once(a, 'webrtc_offer');
  b.emit('webrtc_offer', { offer: { type: 'offer', sdp: 'v=0-test' }, targetSocketId: a.id, callId });
  const off = await withTimeout(offerOnA, 5000, 'webrtc_offer relay');
  ok('A receives webrtc_offer from B (relayed)', off.fromSocketId === b.id && off.offer?.type === 'offer');

  const answerOnB = once(b, 'webrtc_answer');
  a.emit('webrtc_answer', { answer: { type: 'answer', sdp: 'v=0-ans' }, targetSocketId: b.id, callId });
  const ans = await withTimeout(answerOnB, 5000, 'webrtc_answer relay');
  ok('B receives webrtc_answer from A (relayed)', ans.fromSocketId === a.id && ans.answer?.type === 'answer');

  const iceOnA = once(a, 'ice_candidate');
  b.emit('ice_candidate', { candidate: { candidate: 'candidate:test', sdpMid: '0', sdpMLineIndex: 0 }, targetSocketId: a.id, callId });
  const ice = await withTimeout(iceOnA, 5000, 'ice_candidate relay');
  ok('A receives ice_candidate from B (relayed)', ice.fromSocketId === b.id && !!ice.candidate);

  // 4. B leaves → A gets call:peer_left.
  const peerLeft = once(a, 'call:peer_left');
  b.emit('call:leave', { callId });
  const pl = await withTimeout(peerLeft, 5000, 'call:peer_left');
  ok('A receives call:peer_left when B hangs up', pl.socketId === b.id);

  a.disconnect();
  b.disconnect();
  console.log(failures === 0 ? '\nCALL SIGNALLING: ALL PASSED ✓' : `\nCALL SIGNALLING: ${failures} FAILURE(S) ✗`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('harness error:', e.message);
  process.exit(1);
});
