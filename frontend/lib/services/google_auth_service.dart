import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/constants/app_config.dart';

/// Thin wrapper over `google_sign_in` v7.
///
/// - **Web:** the account picker comes from a Google-rendered button
///   (`renderButton()`); its result arrives on [events]. `authenticate()` is
///   not supported in the browser.
/// - **Android/iOS:** call [authenticate] to trigger the native picker.
///
/// The Web OAuth client ID is passed as `clientId` on web and `serverClientId`
/// on mobile, so the resulting ID token's audience is the value the backend
/// verifies against.
class GoogleAuthService {
  GoogleAuthService._();
  static final GoogleAuthService instance = GoogleAuthService._();

  Future<void>? _init;

  /// Idempotent initialization.
  Future<void> ensureInitialized() {
    return _init ??= GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? AppConfig.googleWebClientId : null,
      serverClientId: kIsWeb ? null : AppConfig.googleWebClientId,
    );
  }

  /// Sign-in / sign-out events. On web the rendered button funnels through here.
  Stream<GoogleSignInAuthenticationEvent> get events =>
      GoogleSignIn.instance.authenticationEvents;

  /// Interactive sign-in for mobile/desktop. Throws [GoogleSignInException]
  /// (e.g. code `canceled`) if the user dismisses the picker.
  Future<GoogleSignInAccount> authenticate() =>
      GoogleSignIn.instance.authenticate();

  /// True where `authenticate()` is usable (mobile/desktop; false on web).
  bool get supportsAuthenticate =>
      !kIsWeb && GoogleSignIn.instance.supportsAuthenticate();

  Future<void> signOut() => GoogleSignIn.instance.signOut();
}
