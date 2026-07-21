import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/router/app_router.dart';
import '../../data/repositories/api_client.dart';
import '../../services/socket_service.dart';
import '../../services/notification_service.dart';
import 'main_shell.dart';
import '../providers/auth_provider.dart';
import '../providers/call_provider.dart';
import '../providers/pending_requests_provider.dart';
import '../providers/push_provider.dart';
import '../providers/room_provider.dart';
import '../widgets/common/app_avatar.dart';

/// Home tab — two action cards (New room / Join room) and, when logged in, the
/// permanent DM conversations list. Search now lives in its own tab.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _connecting = false; // a socket connect() is in flight

  @override
  void initState() {
    super.initState();
    // Refresh the DM list + open the live socket on first mount (login/app open).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshChats();
      _ensureRealtime();
    });
  }

  // Keep a live socket on the home tab so new DMs update the list instantly —
  // even when we're not inside a chat. The backend auto-joins this socket to the
  // user's personal channel and pings it (dm_activity) on every DM, so a
  // conversation the user had deleted reappears the moment the other person
  // messages, with no manual reload.
  Future<void> _ensureRealtime() async {
    if (!mounted) return;
    if (!ref.read(authProvider).isLoggedIn) return;
    final socket = SocketService.instance;
    if (!socket.isConnected) {
      if (_connecting) return;
      _connecting = true;
      try {
        final token = await ApiClient.instance.accessToken;
        if (!mounted) return; // re-check after the await
        socket.connect(
          const String.fromEnvironment('SOCKET_URL',
              defaultValue: 'http://localhost:8000'),
          accessToken: token,
        );
      } finally {
        _connecting = false;
      }
      // Register this device for push once the authenticated socket is up,
      // unless the user turned notifications off. Wait for the persisted pref
      // to load first so a prior opt-out isn't ignored on cold start.
      await ref.read(pushProvider.notifier).ready;
      if (mounted && ref.read(pushProvider)) {
        NotificationService.instance.init();
      }
    }
    // (Re)register idempotently (off-then-on) so we never stack listeners or
    // hold a stale one after a reconnect.
    // Live friend-request badge: bump the Profile-tab count when one arrives.
    socket.off('chat_request');
    socket.on('chat_request', (_) {
      if (mounted) ref.read(pendingRequestsProvider.notifier).increment();
    });
    socket.off('dm_activity');
    socket.on('dm_activity', (data) {
      if (mounted) _refreshChats();
      // A DM arrived while we're not in that chat → our device has it, so mark
      // it delivered (double grey tick on the sender's side). The server ignores
      // our own messages, so this is safe even for the echo we get as sender.
      final roomId = data is Map ? data['roomId']?.toString() : null;
      if (roomId != null) {
        socket.emit('message_seen', {'roomId': roomId, 'state': 'delivered'});
      }
    });
    // Attach the global call-signalling listeners so incoming calls ring from
    // anywhere. Idempotent (off-then-on inside), and re-run after a reconnect.
    ref.read(callProvider.notifier).registerSignaling();
  }

  void _refreshChats() {
    if (ref.read(authProvider).isLoggedIn) {
      ref.read(roomProvider.notifier).loadPermanent();
      ref.read(pendingRequestsProvider.notifier).load();
    }
  }

  /// Compact conversation timestamp: time today, "Yesterday", weekday this
  /// week, otherwise a short date.
  String _timeLabel(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(local.year, local.month, local.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return DateFormat.jm().format(local);
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat.E().format(local);
    return DateFormat.MMMd().format(local);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final rooms = ref.watch(roomProvider);

    // The shell bumps this whenever we return from a pushed route (e.g. a chat
    // that tore the socket down on exit) — reconnect and reload.
    ref.listen(homeRefreshTick, (_, __) {
      _refreshChats();
      _ensureRealtime();
    });

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.shield, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(AppStrings.appName, style: AppTextStyles.subheading),
          ],
        ),
        actions: [
          if (auth.isLoggedIn)
            IconButton(
              icon: AppAvatar(
                name: auth.user!.displayName,
                imageUrl: auth.user!.avatar,
                size: 32,
              ),
              onPressed: () => context.go(Routes.me),
            )
          else
            TextButton(
              onPressed: () => context.push(Routes.login),
              child: const Text(AppStrings.login),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(roomProvider.notifier).loadPermanent(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ActionCard(
              icon: Icons.add_circle_outline,
              title: AppStrings.newRoom,
              subtitle: AppStrings.newRoomSub,
              color: AppColors.primary,
              onTap: () => context.push(Routes.createRoom),
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.login,
              title: AppStrings.joinRoom,
              subtitle: AppStrings.joinRoomSub,
              color: AppColors.teal,
              onTap: () => context.push(Routes.joinRoom),
            ),
            if (auth.isLoggedIn) _buildChatsList(rooms),
          ],
        ),
      ),
    );
  }

  Widget _buildChatsList(RoomListState rooms) {
    // build() already watches authProvider, so a read here re-runs on mute change.
    final me = ref.read(authProvider).user;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Messages'.toUpperCase(),
            style: AppTextStyles.monoLabel.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 1.5,
            ),
          ),
        ),
        // Only show the full spinner on the FIRST load (empty list). On a
        // background refresh we keep the existing conversations on screen so
        // they don't blink out and reappear.
        if (rooms.loading && rooms.permanentRooms.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else if (rooms.permanentRooms.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child:
                  Text(AppStrings.noChats, style: AppTextStyles.bodySecondary),
            ),
          )
        else
          ...rooms.permanentRooms.map((room) {
            final other = room.other;
            final mute = other == null ? null : me?.muteFor(other.id);
            final muted = mute?.messagesMuted ?? false;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AppAvatar(
                name: other?.displayName ?? room.name,
                imageUrl: other?.avatar,
                showOnlineDot: true,
                isOnline: other?.isOnline ?? false,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(other?.displayName ?? room.name,
                        style: AppTextStyles.body,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (muted)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.notifications_off,
                          size: 14, color: AppColors.textMuted),
                    ),
                  if (room.lastMessageAt != null)
                    Text(_timeLabel(room.lastMessageAt!),
                        style: AppTextStyles.caption),
                ],
              ),
              // Content-free preview by design.
              subtitle: Text(
                room.lastMessagePreview ?? '—',
                style: AppTextStyles.bodySecondary,
              ),
              onTap: () => context.push(
                Routes.chat,
                extra: ChatArgs(
                  isEphemeral: false,
                  roomId: room.roomId,
                  title: other?.displayName ?? room.name,
                  otherUserId: other?.id,
                  avatarUrl: other?.avatar,
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.subheading),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.bodySecondary),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
