import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_colors.dart';
import 'core/constants/app_strings.dart';
import 'core/constants/app_text_styles.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/models/room_model.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/providers/room_provider.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/widgets/call/call_overlay_host.dart';

/// Root widget — wires the router and the single dark theme.
///
/// Session restore is kicked off here, on every page load, rather than only in
/// the splash screen. On web a refresh of a deep route (e.g. /home) rebuilds
/// that screen directly and never mounts the splash, so restoring here is what
/// keeps a logged-in user signed in across reloads.
class CypherFyApp extends ConsumerStatefulWidget {
  const CypherFyApp({super.key});

  @override
  ConsumerState<CypherFyApp> createState() => _CypherFyAppState();
}

class _CypherFyAppState extends ConsumerState<CypherFyApp> {
  final _router = buildRouter();

  // Notifications: a message the app was launched-from (processed after restore),
  // the in-app foreground banner, and its stream subscriptions.
  RemoteMessage? _pendingTap;
  _ForegroundNotice? _notice;
  Timer? _noticeTimer;
  final _subs = <StreamSubscription<dynamic>>[];

  @override
  void initState() {
    super.initState();
    _wireNotifications();
    // Defer past the first frame — restore() mutates provider state.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _noticeTimer?.cancel();
    super.dispose();
  }

  // ---- Push notifications: taps + foreground banners ------------------

  void _wireNotifications() {
    try {
      // Tapped while the app was backgrounded (already running).
      _subs.add(FirebaseMessaging.onMessageOpenedApp.listen((m) {
        if (ref.read(authProvider).isLoggedIn) {
          _handleTap(m);
        } else {
          _pendingTap = m; // e.g. tapped from lock screen before we're ready
        }
      }));
      // Foreground messages → in-app banner (calls are handled by CallPushService).
      _subs.add(FirebaseMessaging.onMessage.listen((m) {
        if (m.data['type'] == 'call') return;
        _showNotice(m);
      }));
      // Launched from a tap while the app was killed — process after restore.
      FirebaseMessaging.instance.getInitialMessage().then((m) {
        if (m != null) _pendingTap = m;
      });
    } catch (e) {
      debugPrint('Notification wiring skipped: $e');
    }
  }

  Future<void> _bootstrap() async {
    // restore() is idempotent, so this cooperates with the splash screen's own
    // await on cold start without firing a second /users/me request.
    try {
      await ref.read(authProvider.notifier).restore();
      if (ref.read(authProvider).isLoggedIn) {
        await ref.read(roomProvider.notifier).loadPermanent();
      }
    } catch (e) {
      debugPrint('App bootstrap error: $e');
    }
    // If launched from a notification tap, open the target now that we're ready.
    final pending = _pendingTap;
    _pendingTap = null;
    if (pending != null && ref.read(authProvider).isLoggedIn) {
      // Let the splash screen finish its own navigation first (it lands on Home
      // ~900ms after restore), so our push stacks cleanly on top.
      await Future.delayed(const Duration(milliseconds: 1100));
      if (mounted) _handleTap(pending, fromColdStart: true);
    }
  }

  /// Route to the target of a tapped notification (message → the DM, request →
  /// the Friends/Requests screen).
  void _handleTap(RemoteMessage m, {bool fromColdStart = false}) {
    if (fromColdStart) _router.go(Routes.home); // clean base beneath the target
    switch (m.data['type']) {
      case 'message':
        final roomId = m.data['roomId']?.toString();
        if (roomId != null && roomId.isNotEmpty) _openDmByRoomId(roomId);
        break;
      case 'chat_request':
        _router.push(Routes.contacts, extra: 2); // open the Requests tab
        break;
    }
  }

  Future<void> _openDmByRoomId(String roomId) async {
    var rooms = ref.read(roomProvider).permanentRooms;
    if (!rooms.any((r) => r.roomId == roomId)) {
      await ref.read(roomProvider.notifier).loadPermanent();
      rooms = ref.read(roomProvider).permanentRooms;
    }
    RoomModel? room;
    for (final r in rooms) {
      if (r.roomId == roomId) {
        room = r;
        break;
      }
    }
    if (room == null) return; // deleted / not a participant → stay on Home
    final other = room.other;
    _router.push(
      Routes.chat,
      extra: ChatArgs(
        isEphemeral: false,
        roomId: room.roomId,
        title: other?.displayName ?? room.name,
        otherUserId: other?.id,
        avatarUrl: other?.avatar,
      ),
    );
  }

  void _showNotice(RemoteMessage m) {
    final n = m.notification;
    final body = (n?.body?.isNotEmpty ?? false) ? n!.body! : _bodyForData(m.data);
    if (body.isEmpty) return;
    setState(() => _notice = _ForegroundNotice(
          title: n?.title ?? AppStrings.appName,
          body: body,
          message: m,
        ));
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  String _bodyForData(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'chat_request':
        return 'New friend request';
      case 'message':
        return 'New message';
      default:
        return '';
    }
  }

  void _dismissNotice() {
    _noticeTimer?.cancel();
    if (mounted) setState(() => _notice = null);
  }

  void _onNoticeTap() {
    final m = _notice?.message;
    _dismissNotice();
    if (m != null) _handleTap(m);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    // Sync the swappable palette to the chosen brightness BEFORE building the
    // theme, so ThemeData and every AppColors.* getter agree. A toggle rebuilds
    // this widget (and thus the whole app) with the new palette.
    AppColors.setDark(isDark);
    final brightness = isDark ? Brightness.dark : Brightness.light;

    return MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(brightness),
      routerConfig: _router,
      // Overlay the call UI above every route so a call rings/connects anywhere.
      builder: (context, child) => Stack(
        children: [
          if (child != null) child,
          const CallOverlayHost(),
          // In-app banner for foreground pushes (message / friend request).
          if (_notice != null)
            _ForegroundBanner(
              notice: _notice!,
              onTap: _onNoticeTap,
              onDismiss: _dismissNotice,
            ),
        ],
      ),
    );
  }
}

/// A foreground push turned into an in-app banner.
class _ForegroundNotice {
  final String title;
  final String body;
  final RemoteMessage message;
  const _ForegroundNotice({
    required this.title,
    required this.body,
    required this.message,
  });
}

/// Tappable top banner shown for a foreground push. Tapping opens the target;
/// it auto-dismisses after a few seconds (handled by the host).
class _ForegroundBanner extends StatelessWidget {
  final _ForegroundNotice notice;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  const _ForegroundBanner({
    required this.notice,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            color: Colors.transparent,
            child: Dismissible(
              key: const ValueKey('fg-notice'),
              direction: DismissDirection.up,
              onDismissed: (_) => onDismiss(),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border, width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shield, size: 20, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(notice.title,
                                style: AppTextStyles.subheading,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(notice.body,
                                style: AppTextStyles.bodySecondary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
