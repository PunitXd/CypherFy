import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webcrypto/webcrypto.dart';

import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../services/crypto_service.dart';

/// Outcome of a login attempt: a normal success, an unverified account that
/// must confirm its email first, or a plain failure (error surfaced in state).
enum LoginResult { success, needsVerification, failed }

/// Authentication + session state.
///
/// Holds the current user and, crucially, the password-derived WRAPPING KEY
/// used to unwrap permanent-room keys. That wrapping key lives ONLY in memory
/// for the session — it is derived at login and dropped at logout. It never
/// touches disk or the network.
class AuthState {
  final UserModel? user;
  final bool loading;
  final String? error;

  const AuthState({this.user, this.loading = false, this.error});

  bool get isLoggedIn => user != null;

  AuthState copyWith({UserModel? user, bool? loading, String? error, bool clearUser = false}) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState());

  final _repo = AuthRepository();

  /// The in-memory wrapping key derived from the user's password at login.
  /// Consumed by the chat provider to unwrap permanent-room keys.
  AesGcmSecretKey? wrappingKey;

  /// In-flight/completed restore, so the call is made at most once per app
  /// load even when triggered from several places (app root + splash).
  Future<void>? _restoreFuture;

  /// Attempt to restore a session from a stored token (no wrapping key — the
  /// user must re-enter their password to unwrap permanent-room keys).
  ///
  /// Idempotent: repeated calls return the same in-flight future. This matters
  /// on web, where a page refresh on a deep route (e.g. /home) skips the splash
  /// screen — the app root also drives restore so the session survives a reload.
  Future<void> restore() => _restoreFuture ??= _restore();

  Future<void> _restore() async {
    state = state.copyWith(loading: true);
    try {
      final user = await _repo.getMe();
      state = AuthState(user: user, loading: false);
    } catch (_) {
      state = const AuthState(loading: false);
    }
  }

  Future<LoginResult> login(String email, String password) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final user = await _repo.login(email: email, password: password);
      // Derive the wrapping key from the password + user id. Kept in memory.
      wrappingKey = await CryptoService.deriveWrappingKey(password, user.id);
      state = AuthState(user: user, loading: false);
      return LoginResult.success;
    } on DioException catch (e) {
      // Unverified account → the backend returns 403 + verificationRequired and
      // has re-sent a fresh code; route the user to the verification screen.
      final data = e.response?.data;
      final needsVerify = e.response?.statusCode == 403 &&
          data is Map &&
          data['data'] is Map &&
          (data['data'] as Map)['verificationRequired'] == true;
      if (needsVerify) {
        state = state.copyWith(loading: false);
        return LoginResult.needsVerification;
      }
      state = AuthState(loading: false, error: _friendly(e));
      return LoginResult.failed;
    } catch (e) {
      state = AuthState(loading: false, error: _friendly(e));
      return LoginResult.failed;
    }
  }

  /// Register → the backend emails a code and grants no access yet. Returns true
  /// when the code was sent (caller routes to the verification screen).
  Future<bool> register({
    required String email,
    required String password,
    required String displayName,
    required String username,
  }) async {
    state = state.copyWith(loading: true, error: null);
    try {
      await _repo.register(
        email: email,
        password: password,
        displayName: displayName,
        username: username,
      );
      state = state.copyWith(loading: false);
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: _friendly(e));
      return false;
    }
  }

  /// Confirm the emailed OTP → verified + logged in. [password] is needed to
  /// derive the in-memory wrapping key, exactly as login does.
  Future<bool> verifyEmail({
    required String email,
    required String otp,
    required String password,
  }) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final user = await _repo.verifyEmail(email: email, otp: otp);
      wrappingKey = await CryptoService.deriveWrappingKey(password, user.id);
      state = AuthState(user: user, loading: false);
      return true;
    } catch (e) {
      state = AuthState(loading: false, error: _friendly(e));
      return false;
    }
  }

  Future<void> resendVerification(String email) async {
    try {
      await _repo.resendVerification(email);
    } catch (_) {
      // Best-effort; the screen shows its own cooldown feedback.
    }
  }

  /// Sign in with a Firebase ID token (Google/Apple/… via Firebase Auth).
  /// Password-less like Google — no wrapping key to derive (it's unused anyway;
  /// permanent-room keys derive from the room id).
  Future<bool> signInWithFirebase(String idToken) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final user = await _repo.firebaseSignIn(idToken);
      wrappingKey = null;
      state = AuthState(user: user, loading: false);
      return true;
    } catch (e) {
      state = AuthState(loading: false, error: _friendly(e));
      return false;
    }
  }

  /// Replace the current user in state — e.g. after a profile edit — without
  /// touching the in-memory wrapping key.
  void setUser(UserModel user) => state = state.copyWith(user: user);

  Future<void> logout() async {
    try {
      // Best-effort server-side revocation; never let a network/token failure
      // strand the user in a logged-in UI.
      await _repo.logout();
    } finally {
      wrappingKey = null; // drop the derived key from memory
      _restoreFuture = null; // allow a fresh restore after the next login
      state = const AuthState();
    }
  }

  String _friendly(Object e) {
    // Prefer the server's own message for client errors (4xx) — they're
    // meaningful and specific ("Incorrect code", "Code expired", "…already
    // exists"). Fall back to generic copy otherwise.
    if (e is DioException) {
      final code = e.response?.statusCode ?? 0;
      final data = e.response?.data;
      if (code >= 400 &&
          code < 500 &&
          data is Map &&
          data['message'] is String &&
          (data['message'] as String).isNotEmpty) {
        return data['message'] as String;
      }
    }
    final s = e.toString();
    if (s.contains('401')) return 'Invalid credentials';
    if (s.contains('409')) return 'That email or username is taken';
    return 'Something went wrong. Please try again.';
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());
