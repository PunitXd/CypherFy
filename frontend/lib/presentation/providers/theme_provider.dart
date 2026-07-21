import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the app's dark/light choice and persists it across launches.
///
/// Defaults to dark (the app's original look) until the user flips it. The
/// stored value is read once on construction; [setDark]/[toggle] write through
/// to [SharedPreferences].
class ThemeNotifier extends StateNotifier<bool> {
  ThemeNotifier() : super(true) {
    _load();
  }

  static const _key = 'pref_dark_mode';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(_key);
      if (stored != null && stored != state) state = stored;
    } catch (_) {
      // Prefs unavailable — keep the default (dark).
    }
  }

  Future<void> setDark(bool dark) async {
    if (dark == state) return;
    state = dark;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, dark);
    } catch (_) {
      // Non-fatal — the choice still applies for this session.
    }
  }

  Future<void> toggle() => setDark(!state);
}

/// `true` = dark, `false` = light.
final themeProvider =
    StateNotifierProvider<ThemeNotifier, bool>((ref) => ThemeNotifier());
