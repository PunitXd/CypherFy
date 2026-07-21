/// Build-time configuration supplied via `--dart-define`.
class AppConfig {
  AppConfig._();

  /// Google OAuth **Web** client ID. Used as `clientId` on web and
  /// `serverClientId` on mobile so ID tokens carry it as their audience — the
  /// same value the backend verifies against (`GOOGLE_CLIENT_ID`).
  ///
  /// Pass with: `--dart-define=GOOGLE_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com`
  static const googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static bool get hasGoogleClientId => googleWebClientId.isNotEmpty;
}
