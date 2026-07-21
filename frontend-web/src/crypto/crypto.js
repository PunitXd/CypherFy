// E2EE crypto — a byte-for-byte port of frontend/lib/services/crypto_service.dart
// using the browser's WebCrypto (SubtleCrypto). Flutter's `webcrypto` package
// uses the same SubtleCrypto on web and BoringSSL on mobile, so ciphertext
// produced here decrypts on any CypherFy client and vice-versa — PROVIDED the
// parameters below match exactly.
//
// Wire format for encrypted values: { ct: base64(ciphertext+tag), iv: base64(12-byte iv) }
// WebCrypto's AES-GCM appends the 16-byte auth tag to the ciphertext automatically,
// which is exactly what Flutter does — so the concatenated layout matches.
//
// Key model (must match the Dart source):
//   - Ephemeral rooms  → key derived from the room CODE.
//   - Permanent DMs    → key derived from the ROOM ID.
//   Both via PBKDF2(id.toUpperCase(), salt, 100000, SHA-256) → 256-bit AES-GCM.

const subtle = globalThis.crypto.subtle;
const enc = new TextEncoder();
const dec = new TextDecoder();

const IV_LENGTH = 12; // 96-bit IV, standard for GCM
const PBKDF2_ITERATIONS = 100000;
// Fixed application-level salt for room-key derivation (mirrors the Dart constant).
const ROOM_SALT = 'secretchat-v1-room-key-derivation';

// ---- base64 <-> bytes (browser + Node) ------------------------------------

function bytesToB64(bytes) {
  let bin = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

function b64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i += 1) out[i] = bin.charCodeAt(i);
  return out;
}

// ---- Key derivation --------------------------------------------------------

/**
 * Derive a 256-bit AES-GCM key from a room identifier (code for ephemeral,
 * roomId for permanent). Both participants derive the identical key locally;
 * nothing is transmitted. Runs entirely on the client.
 * @param {string} id room code or room id
 * @returns {Promise<CryptoKey>}
 */
export async function deriveKeyFromCode(id) {
  const keyMaterial = await subtle.importKey(
    'raw',
    enc.encode(id.toUpperCase()),
    'PBKDF2',
    false,
    ['deriveKey']
  );
  return subtle.deriveKey(
    {
      name: 'PBKDF2',
      salt: enc.encode(ROOM_SALT),
      iterations: PBKDF2_ITERATIONS,
      hash: 'SHA-256',
    },
    keyMaterial,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt']
  );
}

// ---- Core encrypt / decrypt ------------------------------------------------

/**
 * Encrypt raw bytes → { ct, iv } (both base64).
 * @param {Uint8Array} data
 * @param {CryptoKey} key
 */
export async function encryptBytes(data, key) {
  const iv = globalThis.crypto.getRandomValues(new Uint8Array(IV_LENGTH));
  const cipher = new Uint8Array(await subtle.encrypt({ name: 'AES-GCM', iv }, key, data));
  return { ct: bytesToB64(cipher), iv: bytesToB64(iv) };
}

/**
 * Decrypt a { ct, iv } payload back to raw bytes.
 * @returns {Promise<Uint8Array>}
 */
export async function decryptBytes(ctB64, ivB64, key) {
  const cipher = b64ToBytes(ctB64);
  const iv = b64ToBytes(ivB64);
  return new Uint8Array(await subtle.decrypt({ name: 'AES-GCM', iv }, key, cipher));
}

/** Encrypt a UTF-8 string (chat text). */
export function encryptText(plaintext, key) {
  return encryptBytes(enc.encode(plaintext), key);
}

/** Decrypt to a UTF-8 string. */
export async function decryptText(ctB64, ivB64, key) {
  return dec.decode(await decryptBytes(ctB64, ivB64, key));
}

// ---- File helpers ----------------------------------------------------------

/**
 * Encrypt file bytes plus its { name, type } metadata under the same room key,
 * each with its own IV. Mirrors Dart's encryptFile.
 * @returns {Promise<{cipherBytes: Uint8Array, iv: string, encMeta: string, metaIv: string, size: number}>}
 */
export async function encryptFile(fileBytes, fileName, mimeType, key) {
  const content = await encryptBytes(fileBytes, key);
  const meta = await encryptText(JSON.stringify({ name: fileName, type: mimeType }), key);
  return {
    cipherBytes: b64ToBytes(content.ct), // raw bytes to upload to R2
    iv: content.iv,
    encMeta: meta.ct,
    metaIv: meta.iv,
    size: fileBytes.length,
  };
}

/** Decrypt a downloaded R2 blob (raw ciphertext bytes + base64 IV) to file bytes. */
export async function decryptFileBytes(cipherBytes, ivB64, key) {
  const iv = b64ToBytes(ivB64);
  return new Uint8Array(await subtle.decrypt({ name: 'AES-GCM', iv }, key, cipherBytes));
}

/** Decrypt file metadata back into { name, type }. */
export async function decryptFileMeta(encMeta, metaIv, key) {
  const json = await decryptText(encMeta, metaIv, key);
  const m = JSON.parse(json);
  return {
    name: typeof m.name === 'string' ? m.name : 'file',
    type: typeof m.type === 'string' ? m.type : 'application/octet-stream',
  };
}

// Exposed for tests / advanced callers.
export const _internals = { bytesToB64, b64ToBytes, ROOM_SALT, PBKDF2_ITERATIONS, IV_LENGTH };
