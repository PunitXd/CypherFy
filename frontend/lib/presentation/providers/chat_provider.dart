import 'dart:async';

import 'package:flutter/foundation.dart'; // also provides Uint8List
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webcrypto/webcrypto.dart';

import '../../data/models/message_model.dart';
import '../../data/repositories/room_repository.dart';
import '../../services/crypto_service.dart';
import '../../services/socket_service.dart';

/// A pending knock the host must approve (locked rooms).
class KnockRequest {
  final String alias;
  final String socketId;
  const KnockRequest({required this.alias, required this.socketId});
}

/// A member currently present in an ephemeral room. Members are anonymous
/// aliases (no account behind them) delivered over the socket presence events.
class RoomMember {
  final String alias;
  final String? socketId; // known when seeded from room_joined; null on join delta
  const RoomMember({required this.alias, this.socketId});
}

/// Drives a single open chat: socket wiring, the room key, and the decrypted
/// message list. One instance is created per chat screen.
///
/// The room key is supplied by the caller:
///   - ephemeral: derived from the room code (see CryptoService)
///   - permanent: unwrapped with the session wrapping key (see auth provider)
///
/// The key lives only in this notifier's memory for the life of the screen.
class ChatState {
  final List<MessageModel> messages;
  final List<String> typingAliases;
  final List<RoomMember> members; // live roster (ephemeral rooms)
  final bool connected;
  final bool ended; // room_ended / room_expired
  final int? expiringSecondsLeft; // set when room_expiring fires

  // Knock flow (locked rooms)
  final bool waitingForAdmission; // joiner: knock sent, awaiting host
  final bool rejected; // joiner: host declined
  final List<KnockRequest> knockRequests; // host: pending approvals

  // Ongoing group call in this ephemeral room (drives the rejoin banner). Null
  // when no call is happening.
  final String? groupCallId;
  final String? groupCallType; // 'audio' | 'video'
  final int groupCallCount; // live participant head-count
  final DateTime? groupCallStartedAt; // when the call began (for the duration)

  final String? errorMessage; // last server `error` event, for the UI

  const ChatState({
    this.messages = const [],
    this.typingAliases = const [],
    this.members = const [],
    this.connected = false,
    this.ended = false,
    this.expiringSecondsLeft,
    this.waitingForAdmission = false,
    this.rejected = false,
    this.knockRequests = const [],
    this.groupCallId,
    this.groupCallType,
    this.groupCallCount = 0,
    this.groupCallStartedAt,
    this.errorMessage,
  });

  ChatState copyWith({
    List<MessageModel>? messages,
    List<String>? typingAliases,
    List<RoomMember>? members,
    bool? connected,
    bool? ended,
    int? expiringSecondsLeft,
    bool? waitingForAdmission,
    bool? rejected,
    List<KnockRequest>? knockRequests,
    String? groupCallId,
    String? groupCallType,
    int? groupCallCount,
    DateTime? groupCallStartedAt,
    bool clearGroupCall = false,
    String? errorMessage,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      typingAliases: typingAliases ?? this.typingAliases,
      members: members ?? this.members,
      connected: connected ?? this.connected,
      ended: ended ?? this.ended,
      expiringSecondsLeft: expiringSecondsLeft,
      waitingForAdmission: waitingForAdmission ?? this.waitingForAdmission,
      rejected: rejected ?? this.rejected,
      knockRequests: knockRequests ?? this.knockRequests,
      groupCallId: clearGroupCall ? null : (groupCallId ?? this.groupCallId),
      groupCallType: clearGroupCall ? null : (groupCallType ?? this.groupCallType),
      groupCallCount: clearGroupCall ? 0 : (groupCallCount ?? this.groupCallCount),
      groupCallStartedAt:
          clearGroupCall ? null : (groupCallStartedAt ?? this.groupCallStartedAt),
      errorMessage: errorMessage,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier({
    required this.roomKey,
    required this.isEphemeral,
    this.code,
    this.roomId,
    this.myAlias,
    this.isHost = false,
    this.isLocked = false,
  }) : super(const ChatState()) {
    _wireSocket();
  }

  final AesGcmSecretKey roomKey;
  final bool isEphemeral;
  final String? code; // ephemeral
  final String? roomId; // permanent
  final String? myAlias;
  final bool isHost;
  final bool isLocked;

  final _socket = SocketService.instance;
  final _roomRepo = RoomRepository();

  // Address a message to the correct room type for emit payloads.
  Map<String, dynamic> get _target =>
      isEphemeral ? {'code': code} : {'roomId': roomId};

  void _wireSocket() {
    _socket.on('room_joined', _onRoomJoined);
    _socket.on('new_message', _onNewMessage);
    _socket.on('message_deleted', _onMessageDeleted);
    _socket.on('reaction_updated', _onReaction);
    _socket.on('receipt_update', _onReceiptUpdate);
    _socket.on('typing_update', _onTyping);
    // Live presence roster (ephemeral rooms).
    _socket.on('user_joined', _onUserJoined);
    _socket.on('user_left', _onUserLeft);
    _socket.on('room_expiring', (d) => state = state.copyWith(
        expiringSecondsLeft: (d['secondsLeft'] as num?)?.toInt() ?? 60));
    _socket.on('room_ended', (_) => state = state.copyWith(ended: true));
    _socket.on('room_expired', (_) => state = state.copyWith(ended: true));
    // Knock flow.
    _socket.on('knock_request', _onKnockRequest); // host
    _socket.on('knock_admitted', _onKnockAdmitted); // joiner
    _socket.on('knock_rejected', _onKnockRejected); // joiner
    // Group-call rejoin banner: a call started/ended in this room.
    _socket.on('call:group_active', _onGroupCallActive);
    _socket.on('call:group_ended', _onGroupCallEnded);
    // Surface server errors so failures aren't silent.
    _socket.on('error', _onServerError);
  }

  void _onGroupCallActive(dynamic data) {
    final startedMs = (data['startedAt'] as num?)?.toInt();
    state = state.copyWith(
      groupCallId: data['callId'] as String?,
      groupCallType: (data['callType'] as String?) ?? 'audio',
      groupCallCount: (data['count'] as num?)?.toInt() ?? 1,
      groupCallStartedAt: startedMs != null
          ? DateTime.fromMillisecondsSinceEpoch(startedMs)
          : null,
    );
  }

  void _onGroupCallEnded(dynamic _) {
    state = state.copyWith(clearGroupCall: true);
  }

  /// Called on every (re)connect. For a locked room a non-host joiner must
  /// knock and wait; everyone else joins directly. Emitting on each connect
  /// keeps room membership alive across reconnects.
  void connectFlow() {
    debugPrint(
        'connectFlow: eph=$isEphemeral locked=$isLocked host=$isHost alias=$myAlias code=$code');
    if (!isEphemeral) {
      _socket.emit('join_permanent', {'roomId': roomId});
      return;
    }
    // Surface any group call already in progress so a rejoin banner can show.
    _socket.emit('call:group_state', {'code': code});
    if (isLocked && !isHost) {
      debugPrint('→ emitting KNOCK on $code as $myAlias');
      _socket.emit('knock', {'code': code, 'alias': myAlias});
      state = state.copyWith(waitingForAdmission: true);
    } else {
      debugPrint('→ emitting JOIN_ROOM on $code as $myAlias');
      _socket.emit('join_room', {'code': code, 'alias': myAlias});
    }
  }

  // ---- Knock: joiner side --------------------------------------------

  void _onKnockAdmitted(dynamic _) {
    // Host approved — perform the real join now.
    state = state.copyWith(waitingForAdmission: false);
    _socket.emit('join_room', {'code': code, 'alias': myAlias});
  }

  void _onKnockRejected(dynamic _) {
    state = state.copyWith(waitingForAdmission: false, rejected: true);
  }

  // ---- Knock: host side ----------------------------------------------

  void _onKnockRequest(dynamic data) {
    debugPrint('◆ KNOCK_REQUEST received: $data');
    final req = KnockRequest(
      alias: data['alias']?.toString() ?? 'Someone',
      socketId: data['socketId']?.toString() ?? '',
    );
    if (state.knockRequests.any((k) => k.socketId == req.socketId)) return;
    state = state.copyWith(knockRequests: [...state.knockRequests, req]);
  }

  void admit(String socketId) {
    _socket.emit('admit_user', {'knockSocketId': socketId, 'code': code});
    _removeKnock(socketId);
  }

  void reject(String socketId) {
    _socket.emit('reject_user', {'knockSocketId': socketId, 'code': code});
    _removeKnock(socketId);
  }

  void _removeKnock(String socketId) {
    state = state.copyWith(
      knockRequests:
          state.knockRequests.where((k) => k.socketId != socketId).toList(),
    );
  }

  void _onServerError(dynamic data) {
    final msg = (data is Map ? data['message'] : null)?.toString() ??
        'Something went wrong';
    state = state.copyWith(errorMessage: msg);
  }

  /// Clear the last error after the UI has shown it.
  void clearError() => state = state.copyWith(errorMessage: null);

  // ---- Inbound handlers ----------------------------------------------

  Future<void> _onRoomJoined(dynamic data) async {
    final rawList = (data['messages'] as List?) ?? [];
    final decrypted = <MessageModel>[];
    for (final raw in rawList) {
      // Map.from tolerates a Map<dynamic,dynamic> from the socket layer.
      final m = MessageModel.fromJson(Map<String, dynamic>.from(raw as Map));
      decrypted.add(await _decrypt(m));
    }
    // Seed the presence roster from the join payload ([{socketId, alias}]),
    // de-duped by alias — right after a refresh the server can briefly list both
    // our old (ghost) and new socket under the same alias.
    final rawUsers = (data['users'] as List?) ?? [];
    final seen = <String>{};
    final members = <RoomMember>[];
    for (final u in rawUsers) {
      final alias = (u['alias'] ?? '').toString();
      if (alias.isEmpty || !seen.add(alias)) continue;
      members.add(RoomMember(alias: alias, socketId: u['socketId']?.toString()));
    }
    state = state.copyWith(
        messages: decrypted, connected: true, members: members);
    // We just loaded history → acknowledge it (read if we're looking at it).
    _markSeen(read: _foreground);
  }

  // A member joined (delta carries alias + color + userCount, no socketId).
  void _onUserJoined(dynamic data) {
    final alias = data['alias']?.toString() ?? '';
    if (alias.isEmpty) return;
    if (state.members.any((m) => m.alias == alias)) return;
    state = state.copyWith(members: [...state.members, RoomMember(alias: alias)]);
  }

  // A member left (delta carries alias + userCount). Remove one match.
  void _onUserLeft(dynamic data) {
    final alias = data['alias']?.toString() ?? '';
    if (alias.isEmpty) return;
    // Never drop ourselves from the roster: right after a refresh the server
    // tears down our OLD socket and broadcasts a user_left carrying our own
    // alias — which would otherwise remove us from our own member list.
    if (alias == myAlias) return;
    var removed = false;
    final next = <RoomMember>[];
    for (final m in state.members) {
      if (!removed && m.alias == alias) {
        removed = true;
        continue;
      }
      next.add(m);
    }
    if (removed) state = state.copyWith(members: next);
  }

  Future<void> _onNewMessage(dynamic data) async {
    final m = MessageModel.fromJson(Map<String, dynamic>.from(data as Map));
    final decrypted = await _decrypt(m);
    // Avoid duplicating a message we already have (e.g. echo + reconnect).
    if (state.messages.any((e) => e.messageId == m.messageId)) return;
    // Their message landed → drop any lingering "typing…" for that sender now.
    _clearTypingFor(m.senderAlias);
    state = state.copyWith(messages: [...state.messages, decrypted]);
    // Someone else's message → report receipt (read if we're looking, else just
    // delivered). Our own echoes don't need acking.
    if (!_isOwn(decrypted)) _markSeen(read: _foreground);
  }

  // ---- Read receipts --------------------------------------------------
  // Whether the chat is currently open AND the app is foregrounded. Drives
  // whether an incoming message is marked read (looking) or only delivered.
  bool _foreground = true;

  bool _isOwn(MessageModel m) => m.senderAlias == myAlias;

  /// Called by the chat screen as its visibility/lifecycle changes. Becoming
  /// visible marks everything read.
  void setForeground(bool value) {
    _foreground = value;
    if (value) _markSeen(read: true);
  }

  /// Tell the room we've delivered/read everything up to the latest message we
  /// didn't send ourselves.
  void _markSeen({required bool read}) {
    String? upToId;
    for (final m in state.messages) {
      if (!_isOwn(m)) upToId = m.messageId; // list is chronological
    }
    if (upToId == null) return;
    _socket.emit('message_seen', {
      ..._target,
      'upToId': upToId,
      'state': read ? 'read' : 'delivered',
    });
  }

  /// A peer reported delivering/reading messages up to [upToAt]. Fold their id
  /// into the receipt lists of every message they received (not their own).
  void _onReceiptUpdate(dynamic data) {
    final by = data['by']?.toString() ?? '';
    final read = data['state']?.toString() == 'read';
    final upToAt = DateTime.tryParse(data['upToAt']?.toString() ?? '');
    if (by.isEmpty || upToAt == null) return;
    var changed = false;
    final next = [
      for (final m in state.messages)
        if (m.senderAlias != by &&
            !m.createdAt.isAfter(upToAt) &&
            (read ? !m.readBy.contains(by) : !m.deliveredTo.contains(by)))
          () {
            changed = true;
            return m.withReceipts(
              deliveredTo: m.deliveredTo.contains(by)
                  ? m.deliveredTo
                  : [...m.deliveredTo, by],
              readBy: read && !m.readBy.contains(by)
                  ? [...m.readBy, by]
                  : m.readBy,
            );
          }()
        else
          m,
    ];
    if (changed) state = state.copyWith(messages: next);
  }

  void _onMessageDeleted(dynamic data) {
    final id = data['messageId'].toString();
    state = state.copyWith(
      messages: state.messages.where((m) => m.messageId != id).toList(),
    );
  }

  void _onReaction(dynamic data) {
    final id = data['messageId'].toString();
    final emoji = data['emoji'] as String;
    final count = (data['count'] as num).toInt();
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          if (m.messageId == id)
            m.copyWithDecrypted(reactions: {...m.reactions, emoji: count})
          else
            m,
      ],
    );
  }

  // Receiver side: per-alias watchdog that clears "typing" if the sender goes
  // silent without a typing_stop reaching us (dropped event, disconnect, …).
  final Map<String, Timer> _typingTimers = {};

  void _onTyping(dynamic data) {
    final alias = data['alias'] as String? ?? '';
    final isTyping = data['isTyping'] as bool? ?? false;
    if (alias.isEmpty || alias == myAlias) return;
    _typingTimers.remove(alias)?.cancel();
    final set = {...state.typingAliases};
    if (isTyping) {
      set.add(alias);
      // The sender refreshes typing_start ~every 1.5s, so 4s without one means
      // they've stopped — clear it even if the typing_stop was lost.
      _typingTimers[alias] = Timer(const Duration(seconds: 4), () {
        _typingTimers.remove(alias);
        if (!mounted) return;
        state = state.copyWith(
          typingAliases:
              state.typingAliases.where((a) => a != alias).toList(),
        );
      });
    } else {
      set.remove(alias);
    }
    state = state.copyWith(typingAliases: set.toList());
  }

  void _clearTypingFor(String alias) {
    _typingTimers.remove(alias)?.cancel();
    if (state.typingAliases.contains(alias)) {
      state = state.copyWith(
        typingAliases: state.typingAliases.where((a) => a != alias).toList(),
      );
    }
  }

  /// Decrypt a message's content in place (text or file metadata).
  Future<MessageModel> _decrypt(MessageModel m) async {
    try {
      if (m.isFile) {
        if (m.encMeta == null || m.metaIv == null) return m;
        final meta =
            await CryptoService.decryptFileMeta(m.encMeta!, m.metaIv!, roomKey);
        return m.copyWithDecrypted(fileName: meta.name, fileType: meta.type);
      }
      if (m.ciphertext == null || m.iv == null) return m;
      final text =
          await CryptoService.decryptText(m.ciphertext!, m.iv!, roomKey);
      return m.copyWithDecrypted(decryptedText: text);
    } catch (e) {
      // Undecryptable (wrong key / corrupt) — surface a placeholder.
      if (kDebugMode) print('decrypt failed: $e');
      return m.copyWithDecrypted(decryptedText: '⚠️ unable to decrypt');
    }
  }

  // ---- Outbound actions ----------------------------------------------

  Future<void> sendText(String plaintext, {String? replyTo}) async {
    if (plaintext.trim().isEmpty) return;
    stopTyping(); // sending → we're no longer "typing"
    final enc = await CryptoService.encryptText(plaintext, roomKey);
    _socket.emit('send_message', {
      ..._target,
      'ciphertext': enc.ciphertext,
      'iv': enc.iv,
      'replyTo': replyTo,
    });
  }

  /// Send a file that has already been encrypted and uploaded to R2.
  void sendFile({
    required String blobName,
    required String iv,
    required String encMeta,
    required String metaIv,
    required int size,
    String? replyTo,
  }) {
    _socket.emit('send_file', {
      ..._target,
      'blobName': blobName,
      'iv': iv,
      'encMeta': encMeta,
      'metaIv': metaIv,
      'size': size,
      'replyTo': replyTo,
    });
  }

  /// End-to-end file send: encrypt the bytes + metadata under the room key,
  /// upload the ciphertext to R2 via a presigned URL (the server never sees the
  /// content), then emit the file message.
  Future<void> sendFileBytes(
    Uint8List bytes,
    String name,
    String mimeType, {
    String? replyTo,
  }) async {
    final enc = await CryptoService.encryptFile(bytes, name, mimeType, roomKey);
    final put = await _roomRepo.presignedPut();
    await _roomRepo.uploadBytes(put.url, enc.cipherBytes);
    sendFile(
      blobName: put.blobName,
      iv: enc.iv,
      encMeta: enc.encMeta,
      metaIv: enc.metaIv,
      size: enc.size,
      replyTo: replyTo,
    );
  }

  /// Download a file message's blob from R2 and decrypt it back to plaintext
  /// bytes. Metadata (name/type) is already decrypted on the message model.
  Future<Uint8List> fetchFileBytes(MessageModel m) async {
    final url = await _roomRepo.presignedGet(m.blobName!);
    final cipher = await _roomRepo.downloadBytes(url);
    return CryptoService.decryptFileBytes(cipher, m.iv!, roomKey);
  }

  void react(String messageId, String emoji) {
    _socket.emit('add_reaction', {'messageId': messageId, 'emoji': emoji});
  }

  void deleteMessage(String messageId) {
    _socket.emit('delete_message', {'messageId': messageId});
  }

  // ---- Typing indicator (sender side) --------------------------------
  // Show instantly (emit typing_start on the first keystroke), refresh at most
  // every ~1.5s while typing, and auto-send typing_stop after a short pause — so
  // the other side never sees a stuck "typing…".
  Timer? _typingStopTimer;
  DateTime? _lastTypingSentAt;
  bool _typingActive = false;

  /// Call on every input change. [hasText] = the field currently has content.
  void handleTyping(bool hasText) {
    if (!hasText) {
      stopTyping();
      return;
    }
    final now = DateTime.now();
    if (!_typingActive ||
        _lastTypingSentAt == null ||
        now.difference(_lastTypingSentAt!).inMilliseconds >= 1500) {
      _typingActive = true;
      _lastTypingSentAt = now;
      _socket.emit('typing_start', {..._target});
    }
    // Reset the inactivity timer → stop ~2.5s after the last keystroke.
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(milliseconds: 2500), stopTyping);
  }

  /// Tell the room we've stopped typing (idempotent; also called on send).
  void stopTyping() {
    _typingStopTimer?.cancel();
    _typingStopTimer = null;
    if (_typingActive) {
      _typingActive = false;
      _lastTypingSentAt = null;
      _socket.emit('typing_stop', {..._target});
    }
  }

  void endRoom() {
    if (isEphemeral && code != null) {
      _socket.emit('end_room', {'roomCode': code});
    }
  }

  @override
  void dispose() {
    // Detach listeners so a new chat screen doesn't receive stale events.
    for (final e in [
      'room_joined',
      'new_message',
      'message_deleted',
      'reaction_updated',
      'receipt_update',
      'typing_update',
      'user_joined',
      'user_left',
      'room_expiring',
      'room_ended',
      'room_expired',
      'knock_request',
      'knock_admitted',
      'knock_rejected',
      'error',
    ]) {
      _socket.off(e);
    }
    // Cancel typing timers so they can't fire after disposal.
    _typingStopTimer?.cancel();
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
    super.dispose();
  }
}
