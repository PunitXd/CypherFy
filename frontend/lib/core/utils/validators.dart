/// Reusable form validators returning null when valid, else an error string.
class Validators {
  Validators._();

  static final _emailRegex =
      RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$', caseSensitive: false);
  static final _usernameRegex = RegExp(r'^[a-z0-9_]{3,20}$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(v)) return 'Enter a valid email';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'At least 8 characters';
    return null;
  }

  static String? required(String? value, [String field = 'This field']) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    return null;
  }

  static String? username(String? value) {
    final v = value?.trim().toLowerCase() ?? '';
    if (v.isEmpty) return 'Username is required';
    if (!_usernameRegex.hasMatch(v)) {
      return '3–20 chars: letters, numbers, underscore';
    }
    return null;
  }

  /// Ephemeral room codes are 6 chars from the unambiguous alphabet.
  static String? roomCode(String? value) {
    final v = value?.trim().toUpperCase() ?? '';
    if (v.length != 6) return 'Code must be 6 characters';
    return null;
  }

  static final _otpRegex = RegExp(r'^\d{6}$');

  /// Password-reset OTP: exactly 6 digits.
  static String? otp(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter the 6-digit code';
    if (!_otpRegex.hasMatch(v)) return 'Code must be 6 digits';
    return null;
  }
}
