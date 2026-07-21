import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// A call the user accepted from the native CallKit UI, waiting to be joined
/// once the app/socket is ready (covers the app-was-killed launch path).
class PendingAccept {
  final String callId;
  final bool video;
  final String peerName;
  final String? avatar;
  const PendingAccept({
    required this.callId,
    required this.video,
    required this.peerName,
    this.avatar,
  });
}

/// Bridges FCM call pushes → the native full-screen incoming-call UI
/// (`flutter_callkit_incoming`) and routes the user's Accept/Decline back into
/// [CallNotifier]. This is what lets a killed/backgrounded Android app ring like
/// a normal phone call.
class CallPushService {
  CallPushService._();
  static final CallPushService instance = CallPushService._();

  /// Set when the user taps Accept on the native call UI; consumed by
  /// [CallNotifier] once the socket is up.
  PendingAccept? _pendingAccept;

  /// Registered by [CallNotifier] so an Accept (or the recovery of a pending
  /// one) can join the call, and a Decline can be relayed to the backend.
  void Function(PendingAccept p)? onAccept;
  void Function(String callId)? onDecline;

  bool _wired = false;

  /// Attach the CallKit event listener + a foreground-push fallback. Safe to
  /// call multiple times. No-op on web (the CallKit plugin is mobile-only).
  Future<void> init() async {
    if (kIsWeb || _wired) return;
    _wired = true;

    FlutterCallkitIncoming.onEvent.listen((event) async {
      if (event == null) return;
      final body = event.body;
      final map = body is Map ? body : const {};
      final id = map['id']?.toString();
      switch (event.event) {
        case Event.actionCallAccept:
          if (id != null && id.isNotEmpty) {
            final extra = map['extra'];
            final callType =
                (extra is Map ? extra['callType'] : map['type'])?.toString();
            final p = PendingAccept(
              callId: id,
              video: callType == 'video' || map['type'] == 1,
              peerName: map['nameCaller']?.toString() ?? 'Someone',
              avatar: (map['avatar']?.toString().isNotEmpty ?? false)
                  ? map['avatar'].toString()
                  : null,
            );
            _pendingAccept = p;
            onAccept?.call(p);
          }
          break;
        case Event.actionCallDecline:
        case Event.actionCallTimeout:
          if (id != null && id.isNotEmpty) onDecline?.call(id);
          if (id != null) await FlutterCallkitIncoming.endCall(id);
          break;
        case Event.actionCallEnded:
          _pendingAccept = null;
          break;
        default:
          break;
      }
    });

    // Foreground data pushes are rare (the backend only pushes when the callee
    // has no live socket), but handle them so a call still surfaces if one lands.
    FirebaseMessaging.onMessage.listen((m) {
      if (m.data['type'] == 'call') showIncomingFromData(m.data);
    });
  }

  /// Consume any accept that arrived before [CallNotifier] was ready.
  PendingAccept? takePendingAccept() {
    final p = _pendingAccept;
    _pendingAccept = null;
    return p;
  }

  /// Dismiss every native call UI (after we've joined in-app, or on hang up).
  Future<void> clearNativeCalls() async {
    if (kIsWeb) return;
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {/* non-fatal */}
  }
}

/// Top-level background FCM handler — runs in its own isolate when the app is
/// backgrounded or killed. On a `type:call` data message it raises the native
/// full-screen incoming-call ring.
@pragma('vm:entry-point')
Future<void> firebaseCallBackgroundHandler(RemoteMessage message) async {
  if (message.data['type'] != 'call') return;
  await showIncomingFromData(message.data);
}

/// Show the native incoming-call UI from an FCM `data` payload.
Future<void> showIncomingFromData(Map<String, dynamic> data) async {
  if (kIsWeb) return;
  final callId = data['callId']?.toString() ?? '';
  if (callId.isEmpty) return;
  final callType = data['callType']?.toString() ?? 'audio';
  final avatar = data['callerAvatar']?.toString() ?? '';

  final params = CallKitParams(
    id: callId,
    nameCaller: data['callerName']?.toString() ?? 'Someone',
    appName: 'CypherFy',
    avatar: avatar.isNotEmpty ? avatar : null,
    type: callType == 'video' ? 1 : 0,
    textAccept: 'Accept',
    textDecline: 'Decline',
    // Carry the type so the accept handler knows whether to open the camera.
    extra: {'callType': callType},
    android: const AndroidParams(
      isCustomNotification: true,
      isShowFullLockedScreen: true,
      isImportant: true,
      backgroundColor: '#12100E',
      actionColor: '#4CAF50',
      incomingCallNotificationChannelName: 'Incoming Calls',
      missedCallNotificationChannelName: 'Missed Calls',
    ),
  );
  await FlutterCallkitIncoming.showCallkitIncoming(params);
}
