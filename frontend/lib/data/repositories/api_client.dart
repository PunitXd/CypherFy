import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Shared Dio client with automatic bearer-token injection and a 401 refresh
/// interceptor. Tokens live in flutter_secure_storage.
class ApiClient {
  ApiClient._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'X-Client-Platform': _platform,
        },
      ),
    );
    _dio.interceptors.add(_authInterceptor());
  }

  static final ApiClient instance = ApiClient._();

  // Injected at build via --dart-define; sensible localhost default.
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );

  // Tells the server which session lifetime to mint: web → short (7d, safer on
  // shared machines), mobile → long-lived (stay signed in until logout).
  static const _platform = kIsWeb ? 'web' : 'mobile';

  static const _storage = FlutterSecureStorage();
  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';

  late final Dio _dio;
  Dio get dio => _dio;

  // ---- Token storage --------------------------------------------------

  Future<void> saveTokens(String access, String refresh) async {
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  Future<String?> get accessToken => _storage.read(key: _kAccess);
  Future<String?> get refreshToken => _storage.read(key: _kRefresh);

  Future<void> clearTokens() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }

  // ---- Interceptor ----------------------------------------------------

  InterceptorsWrapper _authInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // On a 401, try a single refresh, then replay the request.
        if (error.response?.statusCode == 401) {
          final refreshed = await _tryRefresh();
          if (refreshed) {
            final req = error.requestOptions;
            final token = await accessToken;
            req.headers['Authorization'] = 'Bearer $token';
            try {
              final clone = await _dio.fetch(req);
              return handler.resolve(clone);
            } catch (_) {
              // fall through to the original error
            }
          }
        }
        handler.next(error);
      },
    );
  }

  Future<bool> _tryRefresh() async {
    final refresh = await refreshToken;
    if (refresh == null) return false;
    try {
      // Use a bare Dio so we don't recurse through this interceptor. Still send
      // the platform header so the rotated token keeps the right lifetime.
      final res = await Dio(
        BaseOptions(
          baseUrl: baseUrl,
          headers: {'X-Client-Platform': _platform},
        ),
      ).post(
        '/auth/refresh-token',
        data: {'refreshToken': refresh},
      );
      final data = res.data['data'] as Map<String, dynamic>;
      await saveTokens(
        data['accessToken'] as String,
        data['refreshToken'] as String,
      );
      return true;
    } on DioException catch (e) {
      // Only log the user out if the server EXPLICITLY rejected the refresh
      // token (expired/revoked). Transient failures — no connectivity, timeout,
      // server down — must NOT wipe the session; keep the tokens and retry on
      // the next request/launch so the user stays logged in until they log out.
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        await clearTokens();
      }
      return false;
    } catch (_) {
      // Unexpected non-HTTP error — don't destroy a valid session over it.
      return false;
    }
  }
}
