import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/room_model.dart';
import '../../data/repositories/room_repository.dart';

/// Manages the permanent-room list shown on the home screen and the create/join
/// flows for ephemeral rooms.
class RoomListState {
  final List<RoomModel> permanentRooms;
  final bool loading;

  const RoomListState({this.permanentRooms = const [], this.loading = false});

  RoomListState copyWith({List<RoomModel>? permanentRooms, bool? loading}) {
    return RoomListState(
      permanentRooms: permanentRooms ?? this.permanentRooms,
      loading: loading ?? this.loading,
    );
  }
}

class RoomNotifier extends StateNotifier<RoomListState> {
  RoomNotifier() : super(const RoomListState());

  final _repo = RoomRepository();

  /// Load the user's permanent conversations (call after login).
  Future<void> loadPermanent() async {
    state = state.copyWith(loading: true);
    try {
      final rooms = await _repo.getPermanentRooms();
      state = RoomListState(permanentRooms: rooms, loading: false);
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  Future<RoomModel> createEphemeral({
    required String alias,
    required String name,
    required int maxUsers,
    required int ttlSeconds,
    bool isLocked = false,
  }) {
    return _repo.createEphemeral(
      alias: alias,
      name: name,
      maxUsers: maxUsers,
      ttlSeconds: ttlSeconds,
      isLocked: isLocked,
    );
  }

  Future<RoomModel> validateCode(String code) => _repo.validateCode(code);

  Future<void> deletePermanent(String roomId) async {
    await _repo.deletePermanent(roomId);
    state = state.copyWith(
      permanentRooms:
          state.permanentRooms.where((r) => r.roomId != roomId).toList(),
    );
  }
}

final roomProvider =
    StateNotifierProvider<RoomNotifier, RoomListState>((ref) => RoomNotifier());
