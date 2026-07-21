import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/notification_service.dart';

/// Whether push notifications are enabled on this device. Persisted across
/// launches; defaults to on. Flipping it registers or unregisters the device's
/// FCM token via [NotificationService].
class PushNotifier extends StateNotifier<bool> {
  PushNotifier() : super(true) {
    ready = _load();
  }

  /// Completes once the persisted preference has been read. Await this before
  /// acting on the value at startup, otherwise a prior opt-out can be missed
  /// while [state] is still the default.
  late final Future<void> ready;

  static const _key = 'pref_push_enabled';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(_key);
      if (stored != null && stored != state) state = stored;
    } catch (_) {
      // Prefs unavailable — keep the default (on).
    }
  }

  Future<void> setEnabled(bool on) async {
    if (on == state) return;
    state = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, on);
    } catch (_) {
      // Non-fatal — the choice still applies for this session.
    }
    // Apply immediately: (un)register this device's push token.
    if (on) {
      await NotificationService.instance.init();
    } else {
      await NotificationService.instance.disable();
    }
  }
}

/// `true` = push enabled.
final pushProvider =
    StateNotifierProvider<PushNotifier, bool>((ref) => PushNotifier());
