// Ephemeral-room end-to-end verification against the live backend.
// Creates a room, connects two socket clients, exchanges ENCRYPTED messages,
// and checks decryption + read receipts. Run: node verify-chat.mjs
import { io } from 'socket.io-client';
import { deriveKeyFromCode, encryptText, decryptText } from './src/crypto/crypto.js';

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
  const aliasA = 'HostFox';
  const aliasB = 'GuestOwl';

  const res = await fetch(API + '/rooms', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ createdBy: aliasA, name: 'Verify Room', maxUsers: 2, ttlSeconds: 3600, isLocked: false }),
  });
  const { data } = await res.json();
  const code = data.code;
  console.log('Created room:', code);
  const key = await deriveKeyFromCode(code);

  const a = connect();
  const b = connect();
  await withTimeout(Promise.all([once(a, 'connect'), once(b, 'connect')]), 5000, 'connect');
  console.log('Both sockets connected');

  const aJoined = once(a, 'room_joined');
  const bJoined = once(b, 'room_joined');
  a.emit('join_room', { code, alias: aliasA });
  b.emit('join_room', { code, alias: aliasB });
  const [ja] = await withTimeout(Promise.all([aJoined, bJoined]), 5000, 'join');
  ok('both received room_joined', !!ja);

  // Capture inbound (decrypted) messages on each side.
  let aMsgIdOnB = null;
  const gotOnB = new Promise((r) =>
    b.on('new_message', async (m) => {
      if (m.senderAlias === aliasA) {
        aMsgIdOnB = m.messageId;
        r(await decryptText(m.ciphertext, m.iv, key));
      }
    })
  );
  const gotOnA = new Promise((r) =>
    a.on('new_message', async (m) => {
      if (m.senderAlias === aliasB) r(await decryptText(m.ciphertext, m.iv, key));
    })
  );

  const msgA = 'Hello from A 🔐 secret';
  const msgB = 'Reply from B ✓ 日本語';
  const eA = await encryptText(msgA, key);
  a.emit('send_message', { code, ciphertext: eA.ct, iv: eA.iv, replyTo: null });
  const eB = await encryptText(msgB, key);
  b.emit('send_message', { code, ciphertext: eB.ct, iv: eB.iv, replyTo: null });

  const rB = await withTimeout(gotOnB, 5000, 'B receive');
  const rA = await withTimeout(gotOnA, 5000, 'A receive');
  ok(`B decrypts A's message  (${JSON.stringify(rB)})`, rB === msgA);
  ok(`A decrypts B's message  (${JSON.stringify(rA)})`, rA === msgB);

  // Read receipt: B marks A's message read → A should get receipt_update{by:GuestOwl}.
  const receiptOnA = new Promise((r) => a.on('receipt_update', (d) => r(d)));
  b.emit('message_seen', { code, upToId: aMsgIdOnB, state: 'read' });
  const receipt = await withTimeout(receiptOnA, 5000, 'receipt');
  ok(`A gets read receipt from B (by=${receipt.by}, state=${receipt.state})`, receipt.by === aliasB && receipt.state === 'read');

  // Typing: A starts typing → B should get typing_update.
  const typingOnB = new Promise((r) => b.on('typing_update', (d) => r(d)));
  a.emit('typing_start', { code });
  const typing = await withTimeout(typingOnB, 5000, 'typing');
  ok(`B sees A typing (alias=${typing.alias}, isTyping=${typing.isTyping})`, typing.alias === aliasA && typing.isTyping === true);

  a.disconnect();
  b.disconnect();
  console.log(failures === 0 ? '\nCHAT E2E: ALL PASSED ✓' : `\nCHAT E2E: ${failures} FAILURE(S) ✗`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('harness error:', e.message);
  process.exit(1);
});
