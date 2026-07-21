import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/call_push_service.dart';

/// Entry point. Firebase is initialised here so both Auth (Google sign-in) and
/// FCM share one app. If it isn't configured yet (`flutterfire configure` not
/// run), we swallow the error so the app still runs on email/password.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Native full-screen call ringing (CallKit) is mobile-only — the plugin has
    // no web implementation, so keep all of it off the web path entirely.
    if (!kIsWeb) {
      // Wake the app for incoming calls even when killed/backgrounded: a
      // high-priority data push runs this handler, which raises the native
      // full-screen call UI.
      FirebaseMessaging.onBackgroundMessage(firebaseCallBackgroundHandler);
      // Route the native Accept/Decline taps back into the call flow.
      await CallPushService.instance.init();
    }
  } catch (e) {
    // Not configured yet → Google sign-in and push (incl. call wake) stay off.
    debugPrint('Firebase init skipped: $e');
  }
  runApp(
    // Riverpod's root — every provider is scoped under this.
    const ProviderScope(
      child: _Root(),
    ),
  );
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) => const CypherFyApp();
}
