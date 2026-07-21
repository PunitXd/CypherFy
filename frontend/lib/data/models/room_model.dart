import 'user_model.dart';

/// A room — ephemeral (code-based) or permanent (DM).
class RoomModel {
  final String roomId;
  final String type; // 'ephemeral' | 'permanent'
  final String name;

  // Ephemeral
  final String? code;
  final int maxUsers;
  final bool isLocked;
  final DateTime? expiresAt;
  final bool isHost;

  // Permanent
  final UserModel? other; // the other participant in a DM
  final String? lastMessagePreview; // content-free ("New message")
  final DateTime? lastMessageAt;

  const RoomModel({
    required this.roomId,
    required this.type,
    required this.name,
    this.code,
    this.maxUsers = 2,
    this.isLocked = false,
    this.expiresAt,
    this.isHost = false,
    this.other,
    this.lastMessagePreview,
    this.lastMessageAt,
  });

  bool get isEphemeral => type == 'ephemeral';

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      roomId: (json['roomId'] ?? json['_id']).toString(),
      type: json['type'] as String? ??
          (json['code'] != null ? 'ephemeral' : 'permanent'),
      name: json['name'] as String? ?? 'Cypher Room',
      code: json['code'] as String?,
      maxUsers: json['maxUsers'] as int? ?? 2,
      isLocked: json['isLocked'] as bool? ?? false,
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'].toString())
          : null,
      isHost: json['isHost'] as bool? ?? false,
      other: json['other'] != null
          ? UserModel.fromJson(json['other'] as Map<String, dynamic>)
          : null,
      lastMessagePreview: json['lastMessagePreview'] as String?,
      lastMessageAt: json['lastMessageAt'] != null
          ? DateTime.tryParse(json['lastMessageAt'].toString())
          : null,
    );
  }
}
