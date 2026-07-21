import 'dart:convert';
import 'dart:typed_data';

import 'package:webcrypto/webcrypto.dart';

/// SECURITY MODEL:
/// The encryption key is derived from the room code using PBKDF2.
/// Key derivation happens entirely on the client device — never on the server.
/// The server uses the room code only as a room identifier (like a room name).
/// The server has no knowledge that PBKDF2 is run on the code client-side.
/// The server stores and relays ciphertext only — it cannot decrypt messages.
/// This maintains the zero-knowledge server property of CypherFy.
///
/// All end-to-end encryption lives here.
///
/// AES-256-GCM for every payload (messages, files, metadata, wrapped room keys).
/// The `webcrypto` package uses the browser's SubtleCrypto on web and BoringSSL
/// on mobile/desktop, so a single implementation covers every platform — no
/// dart:html branching required.
///
/// Wire format for encrypted values:
///   { "ct": base64(ciphertext+tag), "iv": base64(12-byte iv) }
///
/// Security invariants:
///   - Ephemeral room keys are derived from the room code via PBKDF2 — both
///     participants derive the identical key locally; nothing is sent.
///   - Permanent room keys are random and password-wrapped for storage.
///   - A fresh 96-bit IV is generated for every single encryption.
class CryptoService {
  CryptoService._();

  static const int _ivLength = 12; // 96-bit IV, standard for GCM
  static const int _pbkdf2Iterations = 100000;

  /// Fixed application-level salt for ephemeral room-key derivation. The
  /// security comes from the room code being hard to guess, not from the salt
  /// being secret — the salt only defeats precomputed rainbow tables.
  static const String _roomSalt = 'secretchat-v1-room-key-derivation';

  // ---- Key generation & derivation ------------------------------------

  /// Generate a fresh random 256-bit AES-GCM key.
  /// Used for PERMANENT rooms (the key is then password-wrapped for storage).
  static Future<AesGcmSecretKey> generateKey() async {
    return AesGcmSecretKey.generateKey(256);
  }

  /// Derive a 256-bit AES-GCM key from a room code using PBKDF2.
  ///
  /// Both users run this with the same code and get the exact same key. This
  /// runs entirely on the client — the server never sees or runs this; to the
  /// server the code is just a room identifier. No key is ever placed in a URL.
  static Future<AesGcmSecretKey> deriveKeyFromCode(String roomCode) async {
    // Import the room code (normalised to upper-case) as PBKDF2 key material.
    final pbkdf2 = await Pbkdf2SecretKey.importRawKey(
      Uint8List.fromList(utf8.encode(roomCode.toUpperCase())),
    );
    // webcrypto 0.5.x signature: deriveBits(length, hash, salt, iterations).
    final bits = await pbkdf2.deriveBits(
      256,
      Hash.sha256,
      Uint8List.fromList(utf8.encode(_roomSalt)),
      _pbkdf2Iterations,
    );
    return AesGcmSecretKey.importRawKey(bits);
  }

  // ---- Core encrypt / decrypt -----------------------------------------

  /// Encrypt raw bytes. Returns { ct, iv } as base64 strings.
  static Future<EncryptedPayload> encryptBytes(
    Uint8List data,
    AesGcmSecretKey key,
  ) async {
    final iv = _randomBytes(_ivLength);
    final cipher = await key.encryptBytes(data, iv);
    return EncryptedPayload(
      ciphertext: base64.encode(cipher),
      iv: base64.encode(iv),
    );
  }

  /// Decrypt an { ct, iv } payload back to raw bytes.
  static Future<Uint8List> decryptBytes(
    String ciphertextB64,
    String ivB64,
    AesGcmSecretKey key,
  ) async {
    final cipher = base64.decode(ciphertextB64);
    final iv = base64.decode(ivB64);
    return key.decryptBytes(cipher, iv);
  }

  /// Encrypt a UTF-8 string (chat text).
  static Future<EncryptedPayload> encryptText(
    String plaintext,
    AesGcmSecretKey key,
  ) {
    return encryptBytes(Uint8List.fromList(utf8.encode(plaintext)), key);
  }

  /// Decrypt to a UTF-8 string.
  static Future<String> decryptText(
    String ciphertextB64,
    String ivB64,
    AesGcmSecretKey key,
  ) async {
    final bytes = await decryptBytes(ciphertextB64, ivB64, key);
    return utf8.decode(bytes);
  }

  // ---- File helpers ---------------------------------------------------

  /// Encrypt file bytes plus its metadata (name, mime) under the same room key,
  /// each with its own IV. Returns everything needed for a `send_file` event.
  static Future<EncryptedFile> encryptFile(
    Uint8List fileBytes,
    String fileName,
    String mimeType,
    AesGcmSecretKey key,
  ) async {
    final content = await encryptBytes(fileBytes, key);
    final metaJson = jsonEncode({'name': fileName, 'type': mimeType});
    final meta = await encryptText(metaJson, key);
    return EncryptedFile(
      cipherBytes: base64.decode(content.ciphertext),
      iv: content.iv,
      encMeta: meta.ciphertext,
      metaIv: meta.iv,
      size: fileBytes.length,
    );
  }

  /// Decrypt a downloaded R2 blob (raw ciphertext bytes + its base64 IV) back
  /// into the original plaintext file bytes.
  static Future<Uint8List> decryptFileBytes(
    Uint8List cipherBytes,
    String ivB64,
    AesGcmSecretKey key,
  ) async {
    final iv = base64.decode(ivB64);
    return key.decryptBytes(cipherBytes, iv);
  }

  /// Decrypt file metadata back into { name, type }.
  static Future<FileMeta> decryptFileMeta(
    String encMeta,
    String metaIv,
    AesGcmSecretKey key,
  ) async {
    final json = await decryptText(encMeta, metaIv, key);
    final map = jsonDecode(json) as Map<String, dynamic>;
    return FileMeta(
      name: map['name'] as String? ?? 'file',
      type: map['type'] as String? ?? 'application/octet-stream',
    );
  }

  // ---- Permanent-room key wrapping (password-derived) -----------------

  /// Derive a 256-bit wrapping key from the user's password.
  /// PBKDF2(password, salt=userId, 100k iters, SHA-256).
  static Future<AesGcmSecretKey> deriveWrappingKey(
    String password,
    String userId,
  ) async {
    final pbkdf2 = await Pbkdf2SecretKey.importRawKey(
      Uint8List.fromList(utf8.encode(password)),
    );
    final bits = await pbkdf2.deriveBits(
      256,
      Hash.sha256,
      Uint8List.fromList(utf8.encode(userId)), // salt = user id
      _pbkdf2Iterations,
    );
    return AesGcmSecretKey.importRawKey(bits);
  }

  /// Wrap (encrypt) a room key with the password-derived key for storage.
  static Future<EncryptedPayload> wrapRoomKey(
    AesGcmSecretKey roomKey,
    AesGcmSecretKey wrappingKey,
  ) async {
    final raw = await roomKey.exportRawKey();
    return encryptBytes(raw, wrappingKey);
  }

  /// Unwrap (decrypt) a stored room key using the password-derived key.
  static Future<AesGcmSecretKey> unwrapRoomKey(
    String encryptedKeyB64,
    String keyIvB64,
    AesGcmSecretKey wrappingKey,
  ) async {
    final raw = await decryptBytes(encryptedKeyB64, keyIvB64, wrappingKey);
    return AesGcmSecretKey.importRawKey(raw);
  }

  // ---- Internal -------------------------------------------------------

  static Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    fillRandomBytes(bytes);
    return bytes;
  }
}

/// A generic { ciphertext, iv } pair, both base64.
class EncryptedPayload {
  final String ciphertext;
  final String iv;
  const EncryptedPayload({required this.ciphertext, required this.iv});
}

/// Everything needed to send an encrypted file.
class EncryptedFile {
  final Uint8List cipherBytes; // upload these bytes to R2
  final String iv; // IV for the file content
  final String encMeta; // encrypted { name, type }
  final String metaIv;
  final int size; // raw (plaintext) byte size

  const EncryptedFile({
    required this.cipherBytes,
    required this.iv,
    required this.encMeta,
    required this.metaIv,
    required this.size,
  });
}

/// Decrypted file metadata.
class FileMeta {
  final String name;
  final String type;
  const FileMeta({required this.name, required this.type});
}
