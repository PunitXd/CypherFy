import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:webcrypto/webcrypto.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../data/models/message_model.dart';
import '../../../data/repositories/api_client.dart';
import '../../../services/active_room_store.dart';
import '../../../services/crypto_service.dart';
import '../../../services/file_saver.dart';
import '../../../services/socket_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/call_provider.dart';
import '../../providers/chat_provider.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/ttl_timer.dart';
import '../../widgets/chat/typing_indicator.dart';
import '../../widgets/common/app_avatar.dart';

/// The chat surface for BOTH room types.
///
/// Boot sequence:
///   1. Import/derive the room key.
///   2. Connect the socket (with the account token if logged in).
///   3. Emit join_room (ephemeral) or join_permanent (account).
///   4. Hand the key to a ChatNotifier which decrypts everything.
class ChatScreen extends ConsumerStatefulWidget {
  final ChatArgs args;
  const ChatScreen({super.key, required this.args});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  StateNotifierProvider<ChatNotifier, ChatState>? _chatProvider;
  bool _booting = true;
  String? _bootError;
  String? _myAlias;
  bool _uploading = false; // a file is being encrypted + uploaded

  // Max file size mirrors backend FILE.MAX_SIZE_BYTES (25 MB).
  static const _maxFileBytes = 25 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Foreground → mark read; background → incoming messages count as delivered
    // only. The chat being open at all is treated as "reading" (WhatsApp-style).
    if (_chatProvider == null) return;
    ref
        .read(_chatProvider!.notifier)
        .setForeground(state == AppLifecycleState.resumed);
  }

  Future<void> _boot() async {
    try {
      final args = widget.args;

      // 1. Obtain the room key.
      final AesGcmSecretKey key;
      if (args.isEphemeral) {
        // Derive the key locally from the room code — both participants derive
        // the identical key from the same code. Nothing is transmitted.
        key = await CryptoService.deriveKeyFromCode(args.code!);
      } else {
        // Permanent DMs: both participants derive the key from the shared room
        // id (same PBKDF2 model as ephemeral). No key exchange, no stored keys.
        key = await CryptoService.deriveKeyFromCode(args.roomId!);
      }

      // 2. Connect the socket with the current token (guest → null).
      //    connect() tears down the old socket, so re-attach the global call
      //    listeners here (home attached them, but they were just wiped) — this
      //    keeps incoming calls ringing and outgoing calls working from a chat.
      final token = await ApiClient.instance.accessToken;
      SocketService.instance.connect(
        const String.fromEnvironment('SOCKET_URL',
            defaultValue: 'http://localhost:8000'),
        accessToken: token,
      );
      ref.read(callProvider.notifier).registerSignaling();

      // 3. Build the chat notifier (wires socket listeners).
      // Use the SAME alias throughout the session. The host reuses the alias it
      // created the room with (stored server-side as createdBy) so host actions
      // like End Room and admitting knockers are recognised.
      _myAlias = args.alias ?? _generateJoinAlias();
      // Remember this room so a web refresh restores it instead of dropping to
      // Home. Persist the *resolved* alias so the same identity rejoins.
      ActiveRoomStore.instance.save(args, alias: _myAlias);
      _chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
        return ChatNotifier(
          roomKey: key,
          isEphemeral: args.isEphemeral,
          code: args.code,
          roomId: args.roomId,
          myAlias: _myAlias,
          isHost: args.isHost,
          isLocked: args.isLocked,
        );
      });
      // Force the notifier (and its socket listeners) to be created NOW, before
      // the first join, so no room_joined/new_message event can be missed.
      ref.read(_chatProvider!.notifier);

      // 4. On every connect, run the join/knock flow — fires on the initial
      //    connection AND on any automatic reconnect, so room membership is
      //    never silently lost after a socket drop.
      SocketService.instance.onConnect(() {
        ref.read(_chatProvider!.notifier).connectFlow();
        // Re-attach call listeners after an automatic reconnect too.
        ref.read(callProvider.notifier).registerSignaling();
      });
      // If the socket was already connected by the time we registered onConnect
      // (a race on the restore path, where a socket may already be warm), the
      // connect event won't fire again — join now so the roster/messages sync.
      if (SocketService.instance.isConnected) {
        ref.read(_chatProvider!.notifier).connectFlow();
      }
      setState(() => _booting = false);
    } catch (e) {
      setState(() {
        _bootError = 'Could not open room: $e';
        _booting = false;
      });
    }
  }

  String _generateJoinAlias() {
    // Account users use their display name; guests get a random alias.
    final user = ref.read(authProvider).user;
    if (user != null) return user.displayName;
    // Reuse the same generator style as the create screen.
    return 'Guest${DateTime.now().millisecondsSinceEpoch % 1000}';
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty || _chatProvider == null) return;
    _input.clear();
    await ref.read(_chatProvider!.notifier).sendText(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _confirmEndRoom() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.endRoom),
        content: const Text(AppStrings.endRoomConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.endRoom,
                style: TextStyle(color: AppColors.coral)),
          ),
        ],
      ),
    );
    if (ok == true && _chatProvider != null) {
      ref.read(_chatProvider!.notifier).endRoom();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _scroll.dispose();
    // Left the room (navigated back / replaced) → forget it so a later refresh
    // at Home doesn't resurrect it. A web refresh does NOT run dispose, so the
    // record survives exactly the case we want to restore.
    ActiveRoomStore.instance.clear();
    // Leaving a chat must NOT kill a logged-in user's app-wide socket — otherwise
    // they stop receiving incoming calls (and DM updates) everywhere until they
    // re-open a chat. Keep the connection (its global call listeners persist; the
    // next chat's connect() clears this chat's listeners). Guests have an
    // anonymous, room-scoped socket, so they fully disconnect on leave.
    if (!ref.read(authProvider).isLoggedIn) {
      SocketService.instance.disconnect();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_bootError != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_bootError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final chat = ref.watch(_chatProvider!);
    // Are we in a call, and is it minimized behind the chat?
    final inCall = ref.watch(callProvider.select((c) => c.isActive));
    final callMinimized = ref.watch(callProvider.select((c) => c.minimized));
    final callCount =
        ref.watch(callProvider.select((c) => c.participants.length + 1));
    final callStartedAt = ref.watch(callProvider.select((c) => c.startedAt));
    // React to state changes: auto-scroll, room end, rejection, errors.
    ref.listen(_chatProvider!, (prev, next) {
      if ((prev?.messages.length ?? 0) < next.messages.length) {
        _scrollToBottom();
      }
      if (next.ended) _showEnded();
      if ((prev?.rejected != true) && next.rejected) _showRejected();
      if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!)),
        );
        ref.read(_chatProvider!.notifier).clearError();
      }
    });

    // A non-host waiting to be let into a locked room sees a waiting screen.
    if (chat.waitingForAdmission) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.args.title ?? AppStrings.appName)),
        body: const _WaitingForAdmission(),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(chat),
      body: Column(
        children: [
          // We're in the call but minimized it → tap to jump back in.
          if (inCall && callMinimized)
            _ReturnToCallBanner(
              count: callCount,
              startedAt: callStartedAt,
              onTap: () => ref.read(callProvider.notifier).returnToCall(),
            ),
          // A group call is ongoing in this room and we're not in it → offer to
          // (re)join. Ephemeral rooms only.
          if (widget.args.isEphemeral && chat.groupCallId != null && !inCall)
            _CallBanner(
              isVideo: chat.groupCallType == 'video',
              count: chat.groupCallCount,
              startedAt: chat.groupCallStartedAt,
              onRejoin: () => ref.read(callProvider.notifier).joinGroupCall(
                    callId: chat.groupCallId!,
                    video: chat.groupCallType == 'video',
                    peerName: widget.args.title ?? 'Group call',
                  ),
            ),
          // Host: pending knock requests to admit or reject.
          if (chat.knockRequests.isNotEmpty) _buildKnockBanner(chat),
          if (chat.expiringSecondsLeft != null)
            Container(
              width: double.infinity,
              color: AppColors.coral.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Text(AppStrings.roomExpiringSoon,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.coral),
                  textAlign: TextAlign.center),
            ),
          Expanded(child: _buildMessages(chat)),
          if (chat.typingAliases.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 4, top: 2),
              child: Row(
                children: [
                  const TypingIndicator(),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('${chat.typingAliases.join(", ")} typing…',
                        style: AppTextStyles.caption,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          _buildInputBar(),
        ],
      ),
    );
  }

  /// Host-only banner listing everyone knocking, each with Admit / Reject.
  Widget _buildKnockBanner(ChatState chat) {
    final notifier = ref.read(_chatProvider!.notifier);
    return Container(
      width: double.infinity,
      color: AppColors.primaryDim.withValues(alpha: 0.25),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: chat.knockRequests.map((k) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.door_front_door_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${k.alias} wants to join',
                      style: AppTextStyles.body),
                ),
                TextButton(
                  onPressed: () => notifier.reject(k.socketId),
                  child: Text(AppStrings.reject,
                      style: TextStyle(color: AppColors.coral)),
                ),
                TextButton(
                  onPressed: () => notifier.admit(k.socketId),
                  child: const Text(AppStrings.accept),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showRejected() {
    ActiveRoomStore.instance.clear();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Entry declined'),
        content: const Text('The host declined your request to join.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go(Routes.home);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ChatState chat) {
    final args = widget.args;
    // Permanent DMs: show the partner's avatar + name, tappable to their
    // profile (where Delete conversation lives). Ephemeral: name + code.
    final Widget titleWidget = !args.isEphemeral
        ? InkWell(
            onTap: _openPartnerProfile,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppAvatar(
                  name: args.title ?? '?',
                  imageUrl: args.avatarUrl,
                  size: 34,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(args.title ?? AppStrings.appName,
                        style: AppTextStyles.subheading),
                    const _E2eLabel(),
                  ],
                ),
              ],
            ),
          )
        : InkWell(
            onTap: _openRoomDetail,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield, size: 15, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(args.title ?? AppStrings.appName,
                        style: AppTextStyles.subheading),
                    Icon(Icons.expand_more,
                        size: 18, color: AppColors.textSecondary),
                  ],
                ),
                if (args.code != null) const _E2eLabel(),
              ],
            ),
          );
    return AppBar(
      titleSpacing: 0,
      // Explicit back button: normally pops, but after a refresh-restore the room
      // is the root of the stack (nothing to pop), so fall back to Home.
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(Routes.home);
          }
        },
      ),
      title: titleWidget,
      actions: [
        // Voice + video call. DM: rings the partner. Ephemeral: starts/joins a
        // group call (only once connected to the room).
        if (!args.isEphemeral || chat.connected) ...[
          IconButton(
            tooltip: 'Voice call',
            icon: const Icon(Icons.call),
            onPressed: () => _startCall(video: false),
          ),
          IconButton(
            tooltip: 'Video call',
            icon: const Icon(Icons.videocam),
            onPressed: () => _startCall(video: true),
          ),
        ],
        // Live TTL countdown for ephemeral rooms.
        if (args.isEphemeral && args.expiresAt != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: TtlTimer(expiresAt: args.expiresAt!)),
          ),
        if (args.isEphemeral && chat.connected)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: Icon(Icons.lock, size: 16)),
          ),
        // Host-only End Room for ephemeral rooms.
        if (args.isEphemeral && args.isHost)
          IconButton(
            tooltip: AppStrings.endRoom,
            icon: Icon(Icons.delete_outline, color: AppColors.coral),
            onPressed: _confirmEndRoom,
          ),
        // Permanent rooms: view the partner's profile (delete lives there).
        if (!args.isEphemeral)
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _openPartnerProfile,
          ),
      ],
    );
  }

  void _startCall({required bool video}) {
    final args = widget.args;
    ref.read(callProvider.notifier).startCall(
          roomId: args.isEphemeral ? null : args.roomId,
          code: args.isEphemeral ? args.code : null,
          peerName: args.title ?? (args.isEphemeral ? 'Group' : 'Call'),
          peerAvatar: args.avatarUrl,
          video: video,
          isGroup: args.isEphemeral,
        );
  }

  void _openPartnerProfile() {
    final id = widget.args.otherUserId;
    if (id == null) return;
    context.push('${Routes.profile}?userId=$id');
  }

  void _openRoomDetail() {
    if (_chatProvider == null) return;
    context.push(
      Routes.roomDetail,
      extra: RoomDetailArgs(
        chat: widget.args,
        myAlias: _myAlias,
        provider: _chatProvider!,
      ),
    );
  }

  Widget _buildMessages(ChatState chat) {
    if (chat.messages.isEmpty) {
      return Center(
        child: Text('No messages yet', style: AppTextStyles.bodySecondary),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: chat.messages.length,
      itemBuilder: (context, i) {
        final m = chat.messages[i];
        final isMine = _isMine(m);
        // Insert a date divider whenever the calendar day changes.
        final prev = i > 0 ? chat.messages[i - 1] : null;
        final showDivider = prev == null ||
            !_sameDay(prev.createdAt.toLocal(), m.createdAt.toLocal());
        // Group consecutive messages from the same sender (hide repeat avatar).
        final showSender = prev == null ||
            prev.senderAlias != m.senderAlias ||
            showDivider;
        final bubble = MessageBubble(
          message: m,
          isMine: isMine,
          showSender: showSender,
          senderColor: AppColors.aliasColors[
              m.senderAlias.hashCode.abs() % AppColors.aliasColors.length],
          status: isMine ? _statusFor(m, chat) : null,
          onLongPress: () => _showMessageActions(m),
          onFileTap: m.isFile ? () => _downloadFile(m) : null,
        );
        if (!showDivider) return bubble;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DateDivider(date: m.createdAt.toLocal()),
            bubble,
          ],
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isMine(MessageModel m) {
    // Permanent rooms: match by account id. Ephemeral: match by the alias we
    // joined with (now stable and consistent server-side).
    final user = ref.read(authProvider).user;
    if (!widget.args.isEphemeral && user != null) return m.senderId == user.id;
    return m.senderAlias == _myAlias;
  }

  /// Read-receipt state for one of MY messages. DMs track by the partner's
  /// userId; rooms require EVERY current member (besides me) to deliver/read.
  MessageStatus _statusFor(MessageModel m, ChatState chat) {
    final List<String> recipients;
    if (widget.args.isEphemeral) {
      recipients = chat.members
          .map((mem) => mem.alias)
          .where((a) => a != _myAlias)
          .toList();
    } else {
      final other = widget.args.otherUserId;
      recipients = other == null ? const [] : [other];
    }
    if (recipients.isEmpty) return MessageStatus.sent;
    if (recipients.every((r) => m.readBy.contains(r))) return MessageStatus.read;
    if (recipients.every((r) => m.deliveredTo.contains(r))) {
      return MessageStatus.delivered;
    }
    return MessageStatus.sent;
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.attach_file,
                      color: AppColors.textSecondary),
              onPressed: _uploading ? null : _pickAndSendFile,
            ),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                style: AppTextStyles.body,
                decoration: const InputDecoration(
                  hintText: AppStrings.messageHint,
                  border: InputBorder.none,
                ),
                onChanged: (v) => ref
                    .read(_chatProvider!.notifier)
                    .handleTyping(v.trim().isNotEmpty),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
              icon: Icon(Icons.send, color: AppColors.primary),
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }

  void _showMessageActions(MessageModel m) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceEl,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              children: ['👍', '❤️', '😂', '🔥'].map((e) {
                return IconButton(
                  icon: Text(e, style: const TextStyle(fontSize: 22)),
                  onPressed: () {
                    ref.read(_chatProvider!.notifier).react(m.messageId, e);
                    Navigator.pop(ctx);
                  },
                );
              }).toList(),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () {
                ref.read(_chatProvider!.notifier).deleteMessage(m.messageId);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEnded() {
    ActiveRoomStore.instance.clear();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.roomEnded),
        content: const Text('All messages and files have been deleted.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go(Routes.home);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Pick a file, encrypt it, upload the ciphertext to R2, and send the message.
  Future<void> _pickAndSendFile() async {
    if (_uploading || _chatProvider == null) return;
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null) return;

    if (bytes.length > _maxFileBytes) {
      _snack('File too large — max 25 MB');
      return;
    }

    setState(() => _uploading = true);
    try {
      await ref.read(_chatProvider!.notifier).sendFileBytes(
            Uint8List.fromList(bytes),
            picked.name,
            _mimeFor(picked.name),
          );
    } catch (e) {
      _snack('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Download a file message, decrypt it, and hand the bytes to the platform
  /// saver (a browser download on web).
  Future<void> _downloadFile(MessageModel m) async {
    if (m.blobName == null) return;
    _snack('Downloading ${m.fileName ?? 'file'}…');
    try {
      final bytes = await ref.read(_chatProvider!.notifier).fetchFileBytes(m);
      await saveFile(
        bytes,
        m.fileName ?? 'file',
        m.fileType ?? 'application/octet-stream',
      );
    } catch (e) {
      _snack('Download failed: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Minimal extension → MIME guess (kept small; the exact type only affects
  /// how the browser offers the downloaded file).
  String _mimeFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    const map = {
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'pdf': 'application/pdf',
      'txt': 'text/plain',
      'mp4': 'video/mp4',
      'mp3': 'audio/mpeg',
      'zip': 'application/zip',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    };
    return map[ext] ?? 'application/octet-stream';
  }
}

/// Small "shield · E2E Encrypted" caption shown under a chat title.
/// Ongoing-group-call banner with a live head-count and running duration, plus a
/// Rejoin button. Ticks once a second so the duration stays current.
class _CallBanner extends StatefulWidget {
  final bool isVideo;
  final int count;
  final DateTime? startedAt;
  final VoidCallback onRejoin;
  const _CallBanner({
    required this.isVideo,
    required this.count,
    required this.startedAt,
    required this.onRejoin,
  });

  @override
  State<_CallBanner> createState() => _CallBannerState();
}

class _CallBannerState extends State<_CallBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _subtitle {
    final n = widget.count < 1 ? 1 : widget.count;
    final people = '$n ${n == 1 ? 'person' : 'people'}';
    final started = widget.startedAt;
    if (started == null) return 'On call · $people';
    final d = DateTime.now().difference(started);
    final mm = d.inMinutes.toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$people · $mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.primary.withValues(alpha: 0.14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(widget.isVideo ? Icons.videocam : Icons.call,
              size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.isVideo ? 'Group video call' : 'Group call',
                    style: AppTextStyles.body, overflow: TextOverflow.ellipsis),
                Text(_subtitle,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.primary)),
              ],
            ),
          ),
          TextButton(onPressed: widget.onRejoin, child: const Text('Rejoin')),
        ],
      ),
    );
  }
}

/// Shown when the current user has minimized an active call — a full-width green
/// bar (with live head-count + duration) to jump back into the call screen.
class _ReturnToCallBanner extends StatefulWidget {
  final int count;
  final DateTime? startedAt;
  final VoidCallback onTap;
  const _ReturnToCallBanner({
    required this.count,
    required this.startedAt,
    required this.onTap,
  });

  @override
  State<_ReturnToCallBanner> createState() => _ReturnToCallBannerState();
}

class _ReturnToCallBannerState extends State<_ReturnToCallBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _subtitle {
    final n = widget.count < 1 ? 1 : widget.count;
    final people = '$n ${n == 1 ? 'person' : 'people'}';
    final started = widget.startedAt;
    if (started == null) return people;
    final d = DateTime.now().difference(started);
    final mm = d.inMinutes.toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$people · $mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1D9E75),
      child: InkWell(
        onTap: widget.onTap,
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.call, size: 18, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Tap to return to the call',
                          style: AppTextStyles.body.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      Text(_subtitle,
                          style: AppTextStyles.caption
                              .copyWith(color: Colors.white70)),
                    ],
                  ),
                ),
                const Icon(Icons.keyboard_arrow_up,
                    size: 20, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _E2eLabel extends StatelessWidget {
  const _E2eLabel();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.shield, size: 13, color: AppColors.primary),
        const SizedBox(width: 4),
        Text('E2E Encrypted',
            style: AppTextStyles.monoLabel
                .copyWith(fontSize: 11, color: AppColors.primary)),
      ],
    );
  }
}

/// Centered date pill separating messages by calendar day.
class _DateDivider extends StatelessWidget {
  final DateTime date;
  const _DateDivider({required this.date});

  String get _label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(date.year, date.month, date.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    return DateFormat('MMM d').format(date).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Text(_label,
              style: AppTextStyles.monoLabel.copyWith(
                fontSize: 10,
                letterSpacing: 1.5,
                color: AppColors.textSecondary,
              )),
        ),
      ),
    );
  }
}

/// Shown to a joiner who has knocked on a locked room and is awaiting the host.
class _WaitingForAdmission extends StatelessWidget {
  const _WaitingForAdmission();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 56, color: AppColors.primary),
          const SizedBox(height: 20),
          Text('Waiting for the host…', style: AppTextStyles.heading),
          const SizedBox(height: 8),
          Text(
            'This room is locked. The host has been asked to let you in.',
            style: AppTextStyles.bodySecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
        ],
      ),
    );
  }
}
