// Crypto interop test harness.  Run: `node src/crypto/crypto.test.mjs`
//
// Proves the WebCrypto module (crypto.js) is byte-compatible with a standard,
// INDEPENDENT AES-256-GCM / PBKDF2-SHA256 implementation (Node's native `crypto`).
// Since Flutter's `webcrypto` is also a standard implementation of the same
// primitives with the same parameters, matching here is strong evidence of
// Flutter interop. A DIRECT Flutter vector is checked in
// frontend/test/crypto_interop_test.dart (see repo docs).
//
// Also prints a JS→Dart vector, and (if a DART_VECTOR env is provided) verifies
// a Flutter→JS vector.

import nodeCrypto from 'node:crypto';
import {
  deriveKeyFromCode,
  encryptText,
  decryptText,
  encryptFile,
  decryptFileBytes,
  decryptFileMeta,
  _internals,
} from './crypto.js';

const { ROOM_SALT, PBKDF2_ITERATIONS } = _internals;
let failures = 0;
const ok = (name, cond) => {
  console.log(`${cond ? '  ✓' : '  ✗ FAIL'} ${name}`);
  if (!cond) failures += 1;
};

// --- Independent reference impl (Node native crypto) ---------------------
function refKey(id) {
  return nodeCrypto.pbkdf2Sync(
    Buffer.from(id.toUpperCase(), 'utf8'),
    Buffer.from(ROOM_SALT, 'utf8'),
    PBKDF2_ITERATIONS,
    32,
    'sha256'
  );
}
function refEncrypt(plaintext, keyBuf) {
  const iv = nodeCrypto.randomBytes(12);
  const c = nodeCrypto.createCipheriv('aes-256-gcm', keyBuf, iv);
  const ct = Buffer.concat([c.update(Buffer.from(plaintext, 'utf8')), c.final()]);
  const tag = c.getAuthTag();
  return { ct: Buffer.concat([ct, tag]).toString('base64'), iv: iv.toString('base64') };
}
function refDecrypt(ctB64, ivB64, keyBuf) {
  const full = Buffer.from(ctB64, 'base64');
  const iv = Buffer.from(ivB64, 'base64');
  const tag = full.subarray(full.length - 16);
  const ct = full.subarray(0, full.length - 16);
  const d = nodeCrypto.createDecipheriv('aes-256-gcm', keyBuf, iv);
  d.setAuthTag(tag);
  return Buffer.concat([d.update(ct), d.final()]).toString('utf8');
}

async function main() {
  const CODE = 'TESTROOM';
  const P1 = 'Interop ✓ 日本語 emoji 🔐 — SecretChat';
  const key = await deriveKeyFromCode(CODE);
  const kBuf = refKey(CODE);

  console.log('Derived keys equal (WebCrypto deriveKey vs Node pbkdf2):');
  // deriveKey is non-extractable; compare indirectly via cross-decrypt below.

  console.log('\n1. JS WebCrypto round-trip:');
  {
    const e = await encryptText(P1, key);
    ok('text encrypt→decrypt', (await decryptText(e.ct, e.iv, key)) === P1);
    const bytes = new Uint8Array([1, 2, 3, 250, 0, 128, 255]);
    const f = await encryptFile(bytes, 'note.txt', 'text/plain', key);
    const back = await decryptFileBytes(f.cipherBytes, f.iv, key);
    ok('file bytes round-trip', Buffer.compare(Buffer.from(back), Buffer.from(bytes)) === 0);
    const meta = await decryptFileMeta(f.encMeta, f.metaIv, key);
    ok('file meta round-trip', meta.name === 'note.txt' && meta.type === 'text/plain');
  }

  console.log('\n2. Interop with independent Node-native crypto:');
  {
    // A) WebCrypto encrypt → Node-native decrypt
    const e = await encryptText(P1, key);
    ok('WebCrypto→Node decrypt', refDecrypt(e.ct, e.iv, kBuf) === P1);
    // B) Node-native encrypt → WebCrypto decrypt
    const r = refEncrypt(P1, kBuf);
    ok('Node→WebCrypto decrypt', (await decryptText(r.ct, r.iv, key)) === P1);
  }

  console.log('\n3. JS→Dart vector (paste into the Flutter interop test):');
  {
    const e = await encryptText(P1, key);
    console.log(`   CODE = '${CODE}'`);
    console.log(`   PLAINTEXT = ${JSON.stringify(P1)}`);
    console.log(`   ct = '${e.ct}'`);
    console.log(`   iv = '${e.iv}'`);
  }

  if (process.env.DART_CT && process.env.DART_IV) {
    console.log('\n4. Flutter→JS vector verification:');
    const got = await decryptText(process.env.DART_CT, process.env.DART_IV, key);
    console.log(`   decrypted: ${JSON.stringify(got)}`);
    ok('Dart→JS decrypt matches expected', got === (process.env.DART_EXPECT || P1));
  }

  console.log(`\n${failures === 0 ? 'ALL PASSED ✓' : `${failures} FAILURE(S) ✗`}`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('harness error:', e);
  process.exit(1);
});
