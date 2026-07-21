// Cross-implementation crypto interop test.
//
// Proves the React WebCrypto module (frontend-web/src/crypto/crypto.js) and the
// Flutter CryptoService produce mutually-decryptable ciphertext.
//
//   JS→Flutter: decrypt a vector produced by `node src/crypto/crypto.test.mjs`.
//   Flutter→JS: encrypt a vector and print it; feed it back to the JS harness via
//               DART_CT / DART_IV / DART_EXPECT env vars to verify.
//
// Run:  flutter test test/crypto_interop_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:cypherfy/services/crypto_service.dart';

void main() {
  const code = 'TESTROOM';

  test('JS→Flutter: a JS WebCrypto vector decrypts in Flutter', () async {
    // Produced by the Node harness (frontend-web/src/crypto/crypto.test.mjs).
    const ct =
        'cZ4Na8W1blNdQnaZwricwz8Pg+w4awXtVc91O+J0sWNeqdiMgyTUMZVtjskgau62mYQCNJa+0GOqQXmYv6PO';
    const iv = 'a8Dp+jbcv4vrkV4k';
    const expected = 'Interop ✓ 日本語 emoji 🔐 — SecretChat';

    final key = await CryptoService.deriveKeyFromCode(code);
    final plaintext = await CryptoService.decryptText(ct, iv, key);
    expect(plaintext, expected);
  });

  test('Flutter→JS: Flutter produces a vector (printed) + self round-trip', () async {
    const plaintext = 'From Flutter → JS 🔓 SecretChat';
    final key = await CryptoService.deriveKeyFromCode(code);
    final enc = await CryptoService.encryptText(plaintext, key);

    // Emit for the JS side to verify:
    //   DART_CT='<ct>' DART_IV='<iv>' DART_EXPECT='<plaintext>' node src/crypto/crypto.test.mjs
    // ignore: avoid_print
    print('DART_VECTOR ct=${enc.ciphertext} iv=${enc.iv} expect=$plaintext');

    final back = await CryptoService.decryptText(enc.ciphertext, enc.iv, key);
    expect(back, plaintext);
  });
}
