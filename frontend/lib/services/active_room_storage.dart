// Platform selector for where the "active room" record is persisted.
//
// On web it MUST be sessionStorage (per-tab): two tabs of the same browser —
// including incognito tabs that share a window — share localStorage, so a
// localStorage-backed store would make them restore the SAME alias and collide
// into one identity after a refresh. sessionStorage is isolated per tab yet
// survives a reload. On non-web there are no refreshable tabs, so it's a no-op.
export 'active_room_storage_stub.dart'
    if (dart.library.html) 'active_room_storage_web.dart';
