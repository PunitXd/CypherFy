import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../data/repositories/user_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pending_requests_provider.dart';
import '../../providers/room_provider.dart';
import '../../widgets/common/app_avatar.dart';
import '../../widgets/common/app_button.dart';

/// Profile screen.
///   - No [userId]  → the logged-in user's own profile (contacts, logout).
///   - With [userId] → another user's profile. The action shown depends on the
///     relationship: Send request → Request sent → Accept → Message. The DM
///     "Chat/Message" button ONLY appears once the request is accepted.
class ProfileScreen extends ConsumerStatefulWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _userRepo = UserRepository();
  ProfileWithRelationship? _rel;
  bool _loading = false;
  bool _busy = false; // an action (send/accept/reject/delete) is in flight

  // Self-profile only: friends count + pending incoming friend requests (badge).
  int _friendsCount = 0;
  int _pendingRequests = 0;

  bool get _isSelf => widget.userId == null;

  @override
  void initState() {
    super.initState();
    if (_isSelf) {
      _loadSelfMeta();
    } else {
      _load();
    }
  }

  /// Fetch the friend count + pending-request count for the badge.
  Future<void> _loadSelfMeta() async {
    try {
      final friends = await _userRepo.getContacts();
      final requests = await _userRepo.getChatRequests();
      final incoming = (requests['incoming'] as List?)?.length ?? 0;
      if (mounted) {
        setState(() {
          _friendsCount = friends.length;
          _pendingRequests = incoming;
        });
        // Keep the global Profile-tab badge in sync with what we just fetched.
        ref.read(pendingRequestsProvider.notifier).set(incoming);
      }
    } catch (_) {
      // Non-fatal — the profile still renders without the counts.
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rel = await _userRepo.getProfileWithRelationship(widget.userId!);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).user;

    // Resolve which user we're rendering.
    final displayName = _isSelf ? me?.displayName : _rel?.user.displayName;
    final username = _isSelf ? me?.username : _rel?.user.username;
    final avatar = _isSelf ? me?.avatar : _rel?.user.avatar;
    final bio = _isSelf ? me?.bio : _rel?.user.bio;
    final isOnline = _isSelf ? false : (_rel?.user.isOnline ?? false);

    final ready = _isSelf ? me != null : (_rel != null && !_loading);
    final muted = !_isSelf &&
        ((_rel?.messagesMuted ?? false) || (_rel?.callsMuted ?? false));

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.profile)),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_isSelf)
                  _selfHeader(displayName ?? '', username ?? '', avatar, bio)
                else
                  _otherHeader(
                      displayName ?? '', username ?? '', avatar, bio, isOnline,
                      muted),
                const SizedBox(height: 24),
                if (_isSelf) ..._selfActions() else ..._otherActions(),
                // Per-user mute — only meaningful for a contact we can hear from.
                if (!_isSelf && (_rel?.isContact ?? false)) ...[
                  const SizedBox(height: 24),
                  const _SectionLabel('Notifications'),
                  const SizedBox(height: 8),
                  _muteCard(),
                ],
                const SizedBox(height: 24),
                _infoCard(
                  isOnline: isOnline,
                  lastSeen: _isSelf ? null : _rel?.user.lastSeenAt,
                ),
              ],
            ),
    );
  }

  /// Stitch "info rows" card — the always-true E2E row plus, for other users,
  /// a real "Last seen" line (no fabricated member-since; the model has none).
  Widget _infoCard({required bool isOnline, DateTime? lastSeen}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          if (!_isSelf && !isOnline && lastSeen != null) ...[
            _infoRow(
              icon: Icons.schedule,
              iconColor: AppColors.textSecondary,
              title: 'Last seen',
              trailing: _relative(lastSeen),
            ),
            const Divider(height: 0.5),
          ],
          _infoRow(
            icon: Icons.shield,
            iconColor: AppColors.teal,
            title: 'End-to-end encrypted chats',
            subtitle: 'Messages are encrypted on your device',
            trailingDot: true,
          ),
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    String? trailing,
    bool trailingDot = false,
    bool chevron = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.body),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.caption),
                ],
              ],
            ),
          ),
          if (trailing != null)
            Text(trailing, style: AppTextStyles.bodySecondary),
          if (trailingDot)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.teal,
              ),
            ),
          if (chevron)
            Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
        ],
      ),
    );
  }

  // ---- Per-user mute --------------------------------------------------

  /// Sentinel "until turned off" — a far-future instant the server just stores.
  static final DateTime _indefinite = DateTime.utc(9999, 1, 1);

  Widget _muteCard() {
    final rel = _rel!;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          _muteRow(
            icon: Icons.notifications_off_outlined,
            title: 'Mute messages',
            until: rel.messagesMutedUntil,
            isCalls: false,
          ),
          const Divider(height: 0.5),
          _muteRow(
            icon: Icons.phone_disabled_outlined,
            title: 'Mute calls',
            until: rel.callsMutedUntil,
            isCalls: true,
          ),
        ],
      ),
    );
  }

  Widget _muteRow({
    required IconData icon,
    required String title,
    required DateTime? until,
    required bool isCalls,
  }) {
    final active = until != null && until.isAfter(DateTime.now());
    return InkWell(
      onTap: () => _openMuteSheet(isCalls: isCalls, current: until),
      child: _infoRow(
        icon: icon,
        iconColor: active ? AppColors.primary : AppColors.textSecondary,
        title: title,
        subtitle: _muteStateLabel(until),
        chevron: true,
      ),
    );
  }

  String _muteStateLabel(DateTime? until) {
    if (until == null || !until.isAfter(DateTime.now())) return 'Off';
    if (until.year >= 9000) return 'Until you turn it back on';
    final now = DateTime.now();
    final t = TimeOfDay.fromDateTime(until).format(context);
    final sameDay =
        until.year == now.year && until.month == now.month && until.day == now.day;
    return sameDay ? 'Until $t' : 'Until ${until.day}/${until.month}, $t';
  }

  Future<void> _openMuteSheet({
    required bool isCalls,
    required DateTime? current,
  }) {
    final now = DateTime.now();
    final active = current != null && current.isAfter(now);
    final options = <(String, DateTime)>[
      ('For 15 minutes', now.add(const Duration(minutes: 15))),
      ('For 1 hour', now.add(const Duration(hours: 1))),
      ('For 8 hours', now.add(const Duration(hours: 8))),
      ('For 1 day', now.add(const Duration(days: 1))),
      ('Until I turn it back on', _indefinite),
    ];
    return showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Icon(isCalls ? Icons.phone_disabled_outlined
                      : Icons.notifications_off_outlined,
                      size: 20, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Text(isCalls ? 'Mute calls' : 'Mute messages',
                      style: AppTextStyles.subheading),
                ],
              ),
            ),
            const Divider(height: 0.5),
            for (final o in options)
              ListTile(
                title: Text(o.$1, style: AppTextStyles.body),
                onTap: () {
                  Navigator.pop(ctx);
                  _applyMute(isCalls: isCalls, until: o.$2);
                },
              ),
            if (active) ...[
              const Divider(height: 0.5),
              ListTile(
                leading: Icon(Icons.volume_up_outlined, color: AppColors.coral),
                title: Text('Unmute',
                    style: AppTextStyles.body.copyWith(color: AppColors.coral)),
                onTap: () {
                  Navigator.pop(ctx);
                  _applyMute(isCalls: isCalls, until: null);
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _applyMute({required bool isCalls, required DateTime? until}) async {
    final id = widget.userId!;
    final prev = _rel;
    // Grab the notifier BEFORE the await — it outlives this widget, so the global
    // mute list still updates even if the user navigates away mid-request (using
    // `ref` after disposal would throw).
    final authNotifier = ref.read(authProvider.notifier);
    // Optimistic local update so the row reflects the change immediately, keeping
    // the OTHER scope's timestamp as it was.
    setState(() {
      _rel = _rel?.withMute(
        messagesUntil: isCalls ? _rel!.messagesMutedUntil : until,
        callsUntil: isCalls ? until : _rel!.callsMutedUntil,
      );
    });
    try {
      final updated = await _userRepo.setMute(
        id,
        updateMessages: !isCalls,
        messagesUntil: isCalls ? null : until,
        updateCalls: isCalls,
        callsUntil: isCalls ? until : null,
      );
      authNotifier.setUser(updated);
      // Sync to the server's truth for this target.
      final m = updated.muteFor(id);
      if (!mounted) return;
      setState(() => _rel = _rel?.withMute(
            messagesUntil: m?.messagesUntil,
            callsUntil: m?.callsUntil,
          ));
      _snack(until == null
          ? (isCalls ? 'Calls unmuted' : 'Messages unmuted')
          : (isCalls ? 'Calls muted' : 'Messages muted'));
    } catch (e) {
      if (mounted) {
        setState(() => _rel = prev); // revert on failure
        _snack('Could not update mute');
      }
    }
  }

  String _relative(DateTime at) {
    final d = DateTime.now().difference(at.toLocal());
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  // ---- Self profile ---------------------------------------------------

  // Instagram-style self header: avatar on the left, name/handle/stat beside it,
  // bio underneath, then a full-width Edit-profile button.
  Widget _selfHeader(String name, String username, String? avatar, String? bio) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppAvatar(name: name.isEmpty ? '?' : name, imageUrl: avatar, size: 84),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppTextStyles.heading),
                  const SizedBox(height: 2),
                  Text('@$username', style: AppTextStyles.bodySecondary),
                  const SizedBox(height: 8),
                  Text(
                    '$_friendsCount ${_friendsCount == 1 ? 'friend' : 'friends'}',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (bio != null && bio.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(bio, style: AppTextStyles.body),
        ],
        const SizedBox(height: 20),
        AppButton(
          label: AppStrings.editProfile,
          secondary: true,
          icon: Icons.edit_outlined,
          onPressed: () => context.push(Routes.editProfile),
        ),
      ],
    );
  }

  // Other users keep the centred layout (with the mute badge).
  Widget _otherHeader(String name, String username, String? avatar, String? bio,
      bool isOnline, bool muted) {
    return Column(
      children: [
        Center(
          child: AppAvatar(
            name: name.isEmpty ? '?' : name,
            imageUrl: avatar,
            size: 96,
            showOnlineDot: true,
            isOnline: isOnline,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(name,
                    style: AppTextStyles.heading, textAlign: TextAlign.center),
              ),
              if (muted) ...[
                const SizedBox(width: 8),
                Icon(Icons.notifications_off,
                    size: 18, color: AppColors.textMuted),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Center(
            child:
                Text('@$username', style: AppTextStyles.bodySecondary)),
        if (bio != null && bio.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(bio, style: AppTextStyles.body, textAlign: TextAlign.center),
        ],
      ],
    );
  }

  List<Widget> _selfActions() => [
        ListTile(
          leading: const Icon(Icons.people_outline),
          title: const Text(AppStrings.friends),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Friend-request indicator — e.g. a red "2" when 2 are pending.
              if (_pendingRequests > 0) ...[
                _CountBadge(count: _pendingRequests),
                const SizedBox(width: 8),
              ],
              Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
          onTap: () async {
            await context.push(Routes.contacts);
            // Returning from Friends may have cleared/changed requests → refresh.
            if (mounted) _loadSelfMeta();
          },
        ),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text(AppStrings.settings),
          trailing: Icon(Icons.chevron_right, color: AppColors.textMuted),
          onTap: () => context.push(Routes.settings),
        ),
      ];

  // ---- Other user's profile — relationship-aware actions --------------

  List<Widget> _otherActions() {
    final rel = _rel!;

    // Already contacts → Message (opens the DM) + Delete conversation.
    if (rel.isContact && rel.roomId != null) {
      return [
        AppButton(
          label: 'Message',
          icon: Icons.chat_bubble_outline,
          onPressed: () => _openChat(rel.roomId!),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: AppStrings.deleteConversation,
          secondary: true,
          icon: Icons.delete_outline,
          loading: _busy,
          onPressed: _confirmDelete,
        ),
      ];
    }

    // They sent me a request → Accept / Reject.
    if (rel.incomingRequestId != null) {
      return [
        AppButton(
          label: 'Accept request',
          icon: Icons.check,
          loading: _busy,
          onPressed: _accept,
        ),
        const SizedBox(height: 12),
        AppButton(label: AppStrings.reject, secondary: true, onPressed: _reject),
      ];
    }

    // I already sent them a request → greyed "Request sent".
    if (rel.outgoingPending) {
      return const [
        AppButton(label: 'Request sent', onPressed: null),
      ];
    }

    // No relationship yet → Send request.
    return [
      AppButton(
        label: AppStrings.sendChatRequest,
        icon: Icons.person_add_alt,
        loading: _busy,
        onPressed: _sendRequest,
      ),
    ];
  }

  void _openChat(String roomId) {
    final u = _rel!.user;
    context.push(
      Routes.chat,
      extra: ChatArgs(
        isEphemeral: false,
        roomId: roomId,
        title: u.displayName,
        otherUserId: u.id,
        avatarUrl: u.avatar,
      ),
    );
  }

  Future<void> _sendRequest() async {
    setState(() => _busy = true);
    try {
      await _userRepo.sendChatRequest(widget.userId!);
      await _load(); // refresh → now shows "Request sent"
      _snack('Request sent');
    } catch (e) {
      _snack('Could not send request: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    final roomNotifier = ref.read(roomProvider.notifier); // capture before await
    try {
      final roomId = await _userRepo.acceptChatRequest(_rel!.incomingRequestId!);
      // Refresh the home DM list, then open the new conversation.
      await roomNotifier.loadPermanent();
      if (mounted) _openChat(roomId);
    } catch (e) {
      _snack('Could not accept: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _busy = true);
    try {
      await _userRepo.rejectChatRequest(_rel!.incomingRequestId!);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.deleteConversation),
        content: const Text(AppStrings.deleteConversationConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.deleteConversation,
                style: TextStyle(color: AppColors.coral)),
          ),
        ],
      ),
    );
    if (ok != true || _rel?.roomId == null) return;

    final roomNotifier = ref.read(roomProvider.notifier); // capture before await
    setState(() => _busy = true);
    try {
      await roomNotifier.deletePermanent(_rel!.roomId!);
      if (mounted) {
        _snack('Conversation deleted on your side');
        context.go(Routes.home);
      }
    } catch (e) {
      _snack('Could not delete: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// A small red pill showing a count (e.g. pending friend requests). Caps at 9+.
class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        textAlign: TextAlign.center,
        style: AppTextStyles.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Small uppercase section label, matching the settings screen style.
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label.toUpperCase(),
          style: AppTextStyles.monoLabel.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
      );
}
