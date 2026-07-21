// Only ever compiled for web (via the conditional import in
// active_room_storage.dart), so dart:html is the right tool here.
//
// sessionStorage is PER-TAB: it survives a page reload (so a refresh restores
// the room) but is NOT shared with other tabs — even incognito tabs sharing a
// window — so each tab keeps its own alias and they never merge into one.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

const _key = 'active_room_v1';

Future<void> writeActiveRoomRaw(String value) async {
  html.window.sessionStorage[_key] = value;
}

Future<String?> readActiveRoomRaw() async {
  return html.window.sessionStorage[_key];
}

Future<void> clearActiveRoomRaw() async {
  html.window.sessionStorage.remove(_key);
}
