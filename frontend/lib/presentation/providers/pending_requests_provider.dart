import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/user_repository.dart';

/// Number of pending INCOMING friend requests — drives the badge on the Profile
/// tab. Seeded from the server, bumped live when a `chat_request` socket event
/// arrives (wired in Home's realtime setup), and reconciled whenever the
/// Friends/Profile screens re-fetch.
class PendingRequestsNotifier extends StateNotifier<int> {
  PendingRequestsNotifier() : super(0);
  final _repo = UserRepository();

  Future<void> load() async {
    try {
      final r = await _repo.getChatRequests();
      state = (r['incoming'] as List?)?.length ?? 0;
    } catch (_) {
      // Non-fatal — leave the current count.
    }
  }

  void set(int n) => state = n < 0 ? 0 : n;
  void increment() => state = state + 1;
  void clear() => state = 0;
}

final pendingRequestsProvider =
    StateNotifierProvider<PendingRequestsNotifier, int>(
        (_) => PendingRequestsNotifier());
