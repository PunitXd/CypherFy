import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'google_auth_service.dart';

/// Signs the user in with Google **through Firebase Auth** and returns a
/// Firebase ID token to exchange with our backend (`POST /auth/firebase`).
///
/// - **Web:** `signInWithPopup` shows Google's native account-picker popup
///   (the Clerk-style "choose an account" flow).
/// - **Mobile:** `google_sign_in` yields a Google ID token, which we convert
///   into a Firebase credential.
///
/// Our own JWTs still drive the session — Firebase is only the identity gate.
class FirebaseAuthService {
  FirebaseAuthService._();
  static final FirebaseAuthService instance = FirebaseAuthService._();

  FirebaseAuth get _auth => FirebaseAuth.instance;

  /// Interactive Google sign-in → Firebase ID token. Returns null if we can't
  /// obtain a token. Throws [FirebaseAuthException] / [GoogleSignInException]
  /// (e.g. on cancel) for the caller to filter.
  Future<String?> signInWithGoogle() async {
    final UserCredential cred;
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        // Always show the account chooser, even with one session active.
        ..setCustomParameters({'prompt': 'select_account'});
      cred = await _auth.signInWithPopup(provider);
    } else {
      await GoogleAuthService.instance.ensureInitialized();
      final account = await GoogleAuthService.instance.authenticate();
      final credential = GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      );
      cred = await _auth.signInWithCredential(credential);
    }
    // force-refresh false: the just-minted token is fresh.
    return cred.user?.getIdToken();
  }

  /// Sign out of Firebase (so the picker reappears next time). Our own session
  /// teardown is handled separately by AuthNotifier.logout().
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // No Firebase app / already signed out — nothing to do.
    }
  }
}
