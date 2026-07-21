import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/repositories/api_client.dart';
import '../../services/call_push_service.dart';
import '../../services/socket_service.dart';
import '../../services/webrtc_service.dart';

/// Lifecycle of a call, from ringing to connected to over.
enum CallStatus { idle, outgoing, incoming, connecting, connected, ended }

/// A remote participant in the call and their video renderer.
class CallParticipant {
  final String socketId;
  final String userId;
  final String name;
  final String? avatar;
  final RTCVideoRenderer renderer;
  bool hasVideo;

  CallParticipant({
    required this.socketId,
    required this.userId,
    required this.name,
    required this.renderer,
    this.avatar,
    this.hasVideo = false,
  });
}

/// A second call ringing in while one is already active (call-waiting).
class PendingCall {
  final String callId;
  final String name;
  final String? avatar;
  final String callType;
  final bool isGroup;

  const PendingCall({
    required this.callId,
    required this.name,
    this.avatar,
    this.callType = 'audio',
    this.isGroup = false,
  });

  bool get isVideo => callType == 'video';
}

/// Immutable snapshot the call UI renders from.
class CallState {
  final CallStatus status;
  final String? callId;
  final String callType; // 'audio' | 'video'
  final bool isGroup;
  final String? peerName; // 1:1 display / incoming ring card
  final String? peerAvatar;
  final bool micOn;
  final bool camOn;
  final bool speakerOn;
  final DateTime? startedAt;
  final RTCVideoRenderer? localRenderer;
  final List<CallParticipant> participants;
  final String? note; // transient end reason, e.g. "Declined"
  final PendingCall? waiting; // a second call ringing during this one
  final String? flash; // brief in-call toast, e.g. "Bob declined" (stays in call)
  final bool minimized; // call hidden behind the chat ("tap to return")

  const CallState({
    this.status = CallStatus.idle,
    this.callId,
    this.callType = 'audio',
    this.isGroup = false,
    this.peerName,
    this.peerAvatar,
    this.micOn = true,
    this.camOn = true,
    this.speakerOn = false,
    this.startedAt,
    this.localRenderer,
    this.participants = const [],
    this.note,
    this.waiting,
    this.flash,
    this.minimized = false,
  });

  bool get isVideo => callType == 'video';
  bool get isActive =>
      status != CallStatus.idle && status != CallStatus.ended;

  CallState copyWith({
    CallStatus? status,
    String? callId,
    String? callType,
    bool? isGroup,
    String? peerName,
    String? peerAvatar,
    bool? micOn,
    bool? camOn,
    bool? speakerOn,
    DateTime? startedAt,
    RTCVideoRenderer? localRenderer,
    List<CallParticipant>? participants,
    String? note,
    PendingCall? waiting,
    bool clearWaiting = false,
    String? flash,
    bool clearFlash = false,
    bool? minimized,
  }) {
    return CallState(
      status: status ?? this.status,
      callId: callId ?? this.callId,
      callType: callType ?? this.callType,
      isGroup: isGroup ?? this.isGroup,
      peerName: peerName ?? this.peerName,
      peerAvatar: peerAvatar ?? this.peerAvatar,
      micOn: micOn ?? this.micOn,
      camOn: camOn ?? this.camOn,
      speakerOn: speakerOn ?? this.speakerOn,
      startedAt: startedAt ?? this.startedAt,
      localRenderer: localRenderer ?? this.localRenderer,
      participants: participants ?? this.participants,
      note: note,
      waiting: clearWaiting ? null : (waiting ?? this.waiting),
      flash: clearFlash ? null : (flash ?? this.flash),
      minimized: minimized ?? this.minimized,
    );
  }
}

/// Orchestrates call signalling (Socket.io) and media (WebRtcService).
class CallNotifier extends StateNotifier<CallState> {
  CallNotifier() : super(const CallState()) {
    _webrtc.onRemoteStream = _onRemoteStream;
    // Accept/Decline from the native (killed/backgrounded) call UI route here.
    // Mobile-only — the CallKit plugin has no web implementation.
    if (!kIsWeb) {
      CallPushService.instance.onAccept = (p) => _joinFromCallkit(p);
      CallPushService.instance.onDecline = _rejectFromNative;
    }
  }

  final _webrtc = WebRtcService.instance;
  final _socket = SocketService.instance;

  final Map<String, CallParticipant> _peers = {};
  RTCVideoRenderer? _localRenderer;

  Timer? _ringTimeout;
  Timer? _flashTimer;
  bool _wired = false;

  // ---- Wiring: attach socket listeners (idempotent; safe after reconnect) ----
  void registerSignaling() {
    for (final e in const [
      'call:incoming',
      'call:started',
      'call:accepted',
      'call:peer_joined',
      'call:peer_left',
      'call:rejected',
      'call:peer_declined',
      'call:cancelled',
      'call:ended',
      'webrtc_offer',
      'webrtc_answer',
      'ice_candidate',
    ]) {
      _socket.off(e);
    }
    _socket.on('call:incoming', _onIncoming);
    _socket.on('call:started', _onStarted);
    _socket.on('call:accepted', _onAccepted);
    _socket.on('call:peer_joined', _onPeerJoined);
    _socket.on('call:peer_left', _onPeerLeft);
    // 1:1 decline ends the caller's call; a group invitee's decline is info only.
    _socket.on('call:rejected', (_) => _end(note: 'Declined'));
    _socket.on('call:peer_declined', _onPeerDeclined);
    _socket.on('call:cancelled', (_) => _end());
    _socket.on('call:ended', (data) {
      // A DM callee with calls turned off → the server ends immediately.
      final unavailable = data is Map && data['reason'] == 'unavailable';
      _end(note: unavailable ? 'User is unavailable' : null);
    });
    _socket.on('webrtc_offer', _onOffer);
    _socket.on('webrtc_answer', _onAnswer);
    _socket.on('ice_candidate', _onCandidate);
    _wired = true;
    // The user may have accepted a call from the native UI before the socket
    // (and these listeners) were ready — join it now.
    _maybeConsumePendingAccept();
  }

  bool get isWired => _wired;

  /// Join a call the user accepted from the native CallKit UI. Works whether the
  /// app was already running (accept fires live) or freshly launched by the
  /// accept (recovered via [registerSignaling]).
  void _maybeConsumePendingAccept() {
    final p = CallPushService.instance.takePendingAccept();
    if (p != null) _joinFromCallkit(p);
  }

  Future<void> _joinFromCallkit(PendingAccept p) async {
    if (state.isActive) return;
    state = CallState(
      status: CallStatus.connecting,
      callId: p.callId,
      callType: p.video ? 'video' : 'audio',
      peerName: p.peerName,
      peerAvatar: p.avatar,
      micOn: true,
      camOn: p.video,
    );
    if (!await _ensureLocalMedia(p.video)) {
      await reject();
      return;
    }
    if (!kIsWeb) WakelockPlus.enable();
    // Emits buffer until the socket connects, so this is safe pre-connection.
    _socket.emit('call:accept', {'callId': p.callId});
    // Dismiss the native ringing UI now that we've taken the call in-app.
    await CallPushService.instance.clearNativeCalls();
  }

  // ---- Outgoing ----
  Future<void> startCall({
    String? roomId,
    String? code,
    required String peerName,
    String? peerAvatar,
    required bool video,
    bool isGroup = false,
  }) async {
    if (state.isActive) return;
    final callType = video ? 'video' : 'audio';

    state = CallState(
      status: CallStatus.outgoing,
      callType: callType,
      isGroup: isGroup,
      peerName: peerName,
      peerAvatar: peerAvatar,
      micOn: true,
      camOn: video,
    );

    if (!await _ensureLocalMedia(video)) {
      await _end(note: 'Permission denied');
      return;
    }
    if (!kIsWeb) WakelockPlus.enable();

    _socket.emit('call:start', {
      if (roomId != null) 'roomId': roomId,
      if (code != null) 'code': code,
      'callType': callType,
    });
    // Ring timeout — give up if no one answers.
    _ringTimeout = Timer(const Duration(seconds: 40), () {
      if (state.status == CallStatus.outgoing) cancel();
    });
  }

  // ---- Incoming ----
  Future<void> acceptIncoming() async {
    if (state.status != CallStatus.incoming || state.callId == null) return;
    _ringStop();
    final video = state.isVideo;
    if (!await _ensureLocalMedia(video)) {
      await reject();
      return;
    }
    if (!kIsWeb) WakelockPlus.enable();
    state = state.copyWith(status: CallStatus.connecting, camOn: video);
    _socket.emit('call:accept', {'callId': state.callId});
  }

  /// Join (or rejoin) an ongoing group call by id — used by the in-chat rejoin
  /// banner. Behaves like accepting: we join the existing mesh via call:accept.
  Future<void> joinGroupCall({
    required String callId,
    required bool video,
    String peerName = 'Group call',
  }) async {
    if (state.isActive) return;
    final callType = video ? 'video' : 'audio';
    state = CallState(
      status: CallStatus.connecting,
      callId: callId,
      callType: callType,
      isGroup: true,
      peerName: peerName,
      micOn: true,
      camOn: video,
    );
    if (!await _ensureLocalMedia(video)) {
      await _end(note: 'Permission denied');
      return;
    }
    if (!kIsWeb) WakelockPlus.enable();
    _socket.emit('call:accept', {'callId': callId});
  }

  Future<void> reject() async {
    _ringStop();
    if (state.callId != null) _socket.emit('call:reject', {'callId': state.callId});
    await _end();
  }

  /// Decline routed from the native (CallKit) call screen. If the socket is up
  /// we reject over it; otherwise (app backgrounded/just-launched, socket down)
  /// we fall back to the REST endpoint so the caller stops ringing immediately.
  Future<void> _rejectFromNative(String callId) async {
    if (_socket.isConnected) {
      _socket.emit('call:reject', {'callId': callId});
      return;
    }
    try {
      await ApiClient.instance.dio.post('/calls/$callId/reject');
    } catch (_) {/* best-effort; caller's ring timeout is the backstop */}
  }

  Future<void> cancel() async {
    if (state.callId != null) {
      _socket.emit('call:cancel', {'callId': state.callId});
    }
    await _end(note: 'Cancelled');
  }

  Future<void> hangUp() async {
    if (state.callId != null) _socket.emit('call:leave', {'callId': state.callId});
    await _end();
  }

  // Hide the call behind the chat (a "tap to return" banner takes over); the
  // call keeps running. [returnToCall] brings the full screen back.
  void minimize() => state = state.copyWith(minimized: true);
  void returnToCall() => state = state.copyWith(minimized: false);

  // ---- In-call controls ----
  void toggleMute() {
    final on = _webrtc.toggleMic();
    state = state.copyWith(micOn: on);
  }

  void toggleCamera() {
    final on = _webrtc.toggleCamera();
    state = state.copyWith(camOn: on);
  }

  Future<void> switchCamera() => _webrtc.switchCamera();

  Future<void> toggleSpeaker() async {
    final on = !state.speakerOn;
    await _webrtc.setSpeakerphone(on);
    state = state.copyWith(speakerOn: on);
  }

  // ---- Signal handlers ----
  void _onIncoming(dynamic data) {
    final from = (data['from'] ?? {}) as Map;
    // Already in a call → offer call-waiting rather than rejecting. Only one
    // waiting call at a time; ignore further ones until this resolves.
    if (state.isActive) {
      if (state.waiting != null) {
        _socket.emit('call:reject', {'callId': data['callId']});
        return;
      }
      state = state.copyWith(
        waiting: PendingCall(
          callId: data['callId'] as String,
          name: from['name'] as String? ?? 'Someone',
          avatar: from['avatar'] as String?,
          callType: (data['callType'] as String?) ?? 'audio',
          isGroup: data['isGroup'] == true,
        ),
      );
      _beep(); // short call-waiting alert, not the full looping ringtone
      return;
    }
    state = CallState(
      status: CallStatus.incoming,
      callId: data['callId'] as String?,
      callType: (data['callType'] as String?) ?? 'audio',
      isGroup: data['isGroup'] == true,
      peerName: from['name'] as String? ?? 'Someone',
      peerAvatar: from['avatar'] as String?,
    );
    _ringStart();
  }

  /// Accept a call-waiting call: end the current call, then pick up the new one.
  Future<void> acceptWaiting() async {
    final p = state.waiting;
    if (p == null) return;
    _ringStop();
    await hangUp(); // leave the current call → state resets to idle
    state = CallState(
      status: CallStatus.incoming,
      callId: p.callId,
      callType: p.callType,
      isGroup: p.isGroup,
      peerName: p.name,
      peerAvatar: p.avatar,
    );
    await acceptIncoming();
  }

  /// Decline a call-waiting call and stay in the current one.
  Future<void> declineWaiting() async {
    final p = state.waiting;
    if (p == null) return;
    _socket.emit('call:reject', {'callId': p.callId});
    _ringStop();
    state = state.copyWith(clearWaiting: true);
  }

  void _onStarted(dynamic data) {
    _webrtc.configure(
      callId: data['callId'] as String,
      iceServers: data['iceServers'] as List<dynamic>?,
    );
    state = state.copyWith(callId: data['callId'] as String);
  }

  Future<void> _onAccepted(dynamic data) async {
    _webrtc.configure(
      callId: data['callId'] as String,
      iceServers: data['iceServers'] as List<dynamic>?,
    );
    state = state.copyWith(status: CallStatus.connecting);
    final peers = (data['peers'] as List?) ?? const [];
    for (final p in peers) {
      final m = p as Map;
      await _ensureParticipant(
        m['socketId'] as String,
        m['userId'] as String? ?? '',
        m['name'] as String? ?? 'Peer',
      );
      // We joined → we initiate the offer to each existing peer.
      await _webrtc.connectToPeer(m['socketId'] as String, initiator: true);
    }
  }

  Future<void> _onPeerJoined(dynamic data) async {
    _ringTimeout?.cancel();
    final sid = data['socketId'] as String;
    final name = data['name'] as String? ?? 'Peer';
    final isNew = !_peers.containsKey(sid);
    await _ensureParticipant(sid, data['userId'] as String? ?? '', name);
    // We're the existing peer → wait for THEIR offer; just show connecting.
    if (state.status == CallStatus.outgoing) {
      state = state.copyWith(status: CallStatus.connecting);
    }
    // Someone new joined the ongoing call → brief "<name> joined" toast.
    if (isNew) _showFlash('$name joined');
  }

  // A group invitee declined → brief in-call toast; the call continues.
  void _onPeerDeclined(dynamic data) {
    if (!state.isActive) return;
    final name = (data is Map ? data['name'] as String? : null) ?? 'Someone';
    _showFlash('$name declined');
  }

  // Show a short-lived in-call toast (join/decline notices), auto-clearing.
  void _showFlash(String message) {
    state = state.copyWith(flash: message);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(seconds: 3), () {
      if (state.flash != null) state = state.copyWith(clearFlash: true);
    });
  }

  Future<void> _onPeerLeft(dynamic data) async {
    final sid = data['socketId'] as String?;
    if (sid == null) return;
    await _webrtc.removePeer(sid);
    final p = _peers.remove(sid);
    await p?.renderer.dispose();
    if (_peers.isEmpty) {
      // Everyone else is gone → leave server-side too, so our membership and
      // in-call marker are cleared (otherwise the next call reports us busy).
      await hangUp();
    } else {
      _sync();
    }
  }

  Future<void> _onOffer(dynamic data) async {
    final from = data['fromSocketId'] as String;
    await _ensureParticipant(from, '', 'Peer');
    await _webrtc.handleOffer(from, Map<String, dynamic>.from(data['offer'] as Map));
  }

  Future<void> _onAnswer(dynamic data) async {
    await _webrtc.handleAnswer(
      data['fromSocketId'] as String,
      Map<String, dynamic>.from(data['answer'] as Map),
    );
  }

  Future<void> _onCandidate(dynamic data) async {
    await _webrtc.handleCandidate(
      data['fromSocketId'] as String,
      data['candidate'] == null
          ? null
          : Map<String, dynamic>.from(data['candidate'] as Map),
    );
  }

  // Remote media arrived for a peer → attach + mark connected.
  Future<void> _onRemoteStream(String socketId, MediaStream stream) async {
    final p = await _ensureParticipant(socketId, '', 'Peer');
    p.renderer.srcObject = stream;
    p.hasVideo = stream.getVideoTracks().isNotEmpty;
    state = state.copyWith(
      status: CallStatus.connected,
      startedAt: state.startedAt ?? DateTime.now(),
      participants: _peers.values.toList(),
    );
  }

  // ---- Helpers ----
  Future<CallParticipant> _ensureParticipant(
      String socketId, String userId, String name) async {
    final existing = _peers[socketId];
    if (existing != null) return existing;
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    final p = CallParticipant(
      socketId: socketId,
      userId: userId,
      name: name,
      renderer: renderer,
    );
    _peers[socketId] = p;
    _sync();
    return p;
  }

  Future<bool> _ensureLocalMedia(bool video) async {
    if (!kIsWeb) {
      if (!(await Permission.microphone.request()).isGranted) return false;
      if (video && !(await Permission.camera.request()).isGranted) return false;
    }
    try {
      await _webrtc.initLocalMedia(video: video);
    } catch (_) {
      return false;
    }
    _localRenderer = RTCVideoRenderer();
    await _localRenderer!.initialize();
    _localRenderer!.srcObject = _webrtc.localStream;
    state = state.copyWith(localRenderer: _localRenderer);
    return true;
  }

  void _sync() => state = state.copyWith(participants: _peers.values.toList());

  void _ringStart() {
    try {
      FlutterRingtonePlayer().playRingtone(looping: true, asAlarm: false);
    } catch (_) {}
  }

  void _ringStop() {
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {}
  }

  // Short one-shot alert for a call-waiting call (we're already on a call).
  void _beep() {
    try {
      FlutterRingtonePlayer().playNotification();
    } catch (_) {}
  }

  Future<void> _end({String? note}) async {
    _ringStop();
    _ringTimeout?.cancel();
    _ringTimeout = null;
    _flashTimer?.cancel();
    _flashTimer = null;
    // Tear down any native call UI still on screen (e.g. remote hung up first).
    await CallPushService.instance.clearNativeCalls();
    await _webrtc.endAll();
    await _localRenderer?.dispose();
    _localRenderer = null;
    for (final p in _peers.values) {
      await p.renderer.dispose();
    }
    _peers.clear();
    if (!kIsWeb) {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
    if (note != null) {
      state = CallState(status: CallStatus.ended, note: note);
      Timer(const Duration(seconds: 2), () {
        if (state.status == CallStatus.ended) state = const CallState();
      });
    } else {
      state = const CallState();
    }
  }
}

final callProvider =
    StateNotifierProvider<CallNotifier, CallState>((ref) => CallNotifier());
