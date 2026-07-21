import 'package:firebase_messaging/firebase_messaging.dart';

import 'socket_service.dart';

/// FCM push notifications.
///
/// Notifications are content-free by design (the server never sends message
/// text). This service just obtains the device token, registers it with the
/// backend, and exposes the foreground message stream so the UI can show an
/// in-app badge/toast.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  FirebaseMessaging get _fm => FirebaseMessaging.instance;

  /// Request permission, fetch the token, and send it to the server over the
  /// authenticated socket. Call after login once the socket is connected.
  Future<void> init() async {
    try {
      await _fm.requestPermission();
      final token = await _fm.getToken();
      if (token != null) {
        SocketService.instance.emit('save_fcm_token', {'token': token});
      }
      // Re-register if the token rotates.
      _fm.onTokenRefresh.listen((newToken) {
        SocketService.instance.emit('save_fcm_token', {'token': newToken});
      });
    } catch (e) {
      // FCM may be unavailable (e.g. web without config) — non-fatal.
      print('Notification init skipped: $e');
    }
  }

  /// Turn push off for this device: unregister the token server-side (so no
  /// more pushes are sent here) and delete it locally. Non-fatal if FCM is
  /// unavailable. Call [init] again to re-enable.
  Future<void> disable() async {
    try {
      final token = await _fm.getToken();
      if (token != null) {
        SocketService.instance.emit('remove_fcm_token', {'token': token});
      }
      await _fm.deleteToken();
    } catch (e) {
      print('Notification disable skipped: $e');
    }
  }

  /// Foreground messages — the UI can subscribe to show a lightweight banner.
  Stream<RemoteMessage> get onForegroundMessage =>
      FirebaseMessaging.onMessage;
}
