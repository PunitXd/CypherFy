import 'dart:convert';

import '../core/router/app_router.dart';
import 'active_room_storage.dart';

/// Remembers the room the user is currently in so a web page refresh — which
/// wipes all in-memory route state, including the `ChatArgs` passed via go_router
/// `extra` — can drop them straight back into that room instead of Home.
///
/// Only what's needed to re-open the room is stored: an ephemeral room's E2E key
/// is re-derived from its code (nothing new is exposed here), and the resolved
/// alias is kept so the same identity rejoins. Cleared the moment the user leaves
/// the room (or it ends), so a refresh at Home never resurrects a stale room.
///
/// Storage is PER-TAB (sessionStorage on web) so two tabs — including incognito
/// tabs that share a window and thus share localStorage — never restore each
/// other's alias and merge into one identity.
class ActiveRoomStore {
  ActiveRoomStore._();
  static final instance = ActiveRoomStore._();

  /// Persist the currently open room. [alias] is the *resolved* alias actually
  /// used to join (a joiner's is generated at runtime, so `args.alias` alone is
  /// not enough to keep identity stable across a refresh).
  Future<void> save(ChatArgs args, {String? alias}) async {
    final map = {
      'isEphemeral': args.isEphemeral,
      'code': args.code,
      'roomId': args.roomId,
      'title': args.title,
      'isHost': args.isHost,
      'expiresAt': args.expiresAt?.millisecondsSinceEpoch,
      'alias': alias ?? args.alias,
      'isLocked': args.isLocked,
      'otherUserId': args.otherUserId,
      'avatarUrl': args.avatarUrl,
    };
    try {
      await writeActiveRoomRaw(jsonEncode(map));
    } catch (_) {
      // Persistence is best-effort; never let it break entering a room.
    }
  }

  Future<void> clear() async {
    try {
      await clearActiveRoomRaw();
    } catch (_) {}
  }

  /// The saved room as [ChatArgs], or null when there is none (or an ephemeral
  /// room has already expired, in which case the stale record is cleared).
  Future<ChatArgs?> read() async {
    String? raw;
    try {
      raw = await readActiveRoomRaw();
    } catch (_) {
      return null;
    }
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final expMs = m['expiresAt'] as int?;
      final expiresAt =
          expMs != null ? DateTime.fromMillisecondsSinceEpoch(expMs) : null;
      final isEphemeral = m['isEphemeral'] as bool? ?? false;
      // An ephemeral room that already lapsed can't be rejoined — drop it.
      if (isEphemeral && expiresAt != null && expiresAt.isBefore(DateTime.now())) {
        await clear();
        return null;
      }
      return ChatArgs(
        isEphemeral: isEphemeral,
        code: m['code'] as String?,
        roomId: m['roomId'] as String?,
        title: m['title'] as String?,
        isHost: m['isHost'] as bool? ?? false,
        expiresAt: expiresAt,
        alias: m['alias'] as String?,
        isLocked: m['isLocked'] as bool? ?? false,
        otherUserId: m['otherUserId'] as String?,
        avatarUrl: m['avatarUrl'] as String?,
      );
    } catch (_) {
      await clear();
      return null;
    }
  }
}
