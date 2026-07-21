import '../models/user_model.dart';
import 'api_client.dart';

/// Auth REST calls. On login/register the tokens are persisted by [ApiClient]
/// and the [UserModel] is returned to the caller.
class AuthRepository {
  final ApiClient _api = ApiClient.instance;

  /// Register → the backend emails a verification code and returns no tokens.
  /// Access is granted only after [verifyEmail].
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    required String username,
  }) async {
    await _api.dio.post('/auth/register', data: {
      'email': email,
      'password': password,
      'displayName': displayName,
      'username': username,
    });
  }

  /// Confirm the emailed OTP → the backend marks the account verified and
  /// returns session tokens (same shape as login).
  Future<UserModel> verifyEmail({
    required String email,
    required String otp,
  }) async {
    final res = await _api.dio.post('/auth/verify-email', data: {
      'email': email,
      'otp': otp,
    });
    final data = res.data['data'] as Map<String, dynamic>;
    await _api.saveTokens(data['accessToken'], data['refreshToken']);
    return UserModel.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> resendVerification(String email) async {
    await _api.dio.post('/auth/resend-verification', data: {'email': email});
  }

  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final res = await _api.dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    final data = res.data['data'] as Map<String, dynamic>;
    await _api.saveTokens(data['accessToken'], data['refreshToken']);
    return UserModel.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// Exchange a Firebase ID token (from any social provider routed through
  /// Firebase Auth) for our own session tokens. Same downstream shape as [login].
  Future<UserModel> firebaseSignIn(String idToken) async {
    final res =
        await _api.dio.post('/auth/firebase', data: {'idToken': idToken});
    final data = res.data['data'];
    await _api.saveTokens(data['accessToken'], data['refreshToken']);
    return UserModel.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    final refresh = await _api.refreshToken;
    try {
      await _api.dio.post('/auth/logout', data: {'refreshToken': refresh});
    } catch (_) {
      // Revocation is best-effort — an expired/invalid token or an offline
      // client must still be able to log out locally.
    } finally {
      await _api.clearTokens();
    }
  }

  Future<void> forgotPassword(String email) async {
    await _api.dio.post('/auth/forgot-password', data: {'email': email});
  }

  /// Verify a password-reset OTP. Returns a one-time ticket to pass to
  /// [resetPassword] as its `token`.
  Future<String> verifyOtp({
    required String email,
    required String otp,
  }) async {
    final res = await _api.dio.post('/auth/verify-otp', data: {
      'email': email,
      'otp': otp,
    });
    return res.data['data']['ticket'] as String;
  }

  Future<void> resetPassword({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    await _api.dio.post('/auth/reset-password', data: {
      'email': email,
      'token': token,
      'newPassword': newPassword,
    });
  }

  /// Change the password while logged in. Sends the current refresh token so the
  /// server keeps this session alive while revoking others.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final refresh = await _api.refreshToken;
    await _api.dio.post('/auth/change-password', data: {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
      'refreshToken': refresh,
    });
  }

  /// Fetch the current user; returns null if not authenticated.
  Future<UserModel?> getMe() async {
    if (await _api.accessToken == null) return null;
    try {
      final res = await _api.dio.get('/users/me');
      return UserModel.fromJson(
        res.data['data']['user'] as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}
