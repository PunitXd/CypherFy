import 'dart:typed_data';

/// Non-web fallback. Saving/opening a decrypted file on mobile/desktop needs
/// path_provider + open_file, which aren't wired in this build.
Future<void> saveFile(Uint8List bytes, String name, String mimeType) async {
  throw UnsupportedError(
    'Downloading files is only wired for web in this build.',
  );
}
