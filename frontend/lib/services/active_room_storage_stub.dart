// Non-web: restoring a room after a page refresh is a web-only concern (mobile
// apps have no refreshable tabs), so persistence is a no-op here.
Future<void> writeActiveRoomRaw(String value) async {}

Future<String?> readActiveRoomRaw() async => null;

Future<void> clearActiveRoomRaw() async {}
