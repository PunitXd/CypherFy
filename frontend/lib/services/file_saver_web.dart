// This file is only ever compiled for web (selected via conditional import),
// so dart:html is the right tool here.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// Web implementation: wrap the decrypted bytes in a Blob and click a temporary
/// anchor to trigger the browser's download of the original file.
Future<void> saveFile(Uint8List bytes, String name, String mimeType) async {
  final blob = html.Blob(<Uint8List>[bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = name
    ..click();
  // Free the object URL once the download has kicked off.
  html.Url.revokeObjectUrl(url);
}
