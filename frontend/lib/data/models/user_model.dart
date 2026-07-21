/// One entry in the current user's per-user mute list. `messagesUntil` /
/// `callsUntil` are the instants each scope stays muted until (a far-future date
/// means "until turned off"); null/past means not muted for that scope.
class MutedUser {
  final String userId;
  final DateTime? messagesUntil;
  final DateTime? callsUntil;

  const MutedUser({required this.userId, this.messagesUntil, this.callsUntil});

  static bool _active(DateTime? until) =>
      until != null && until.isAfter(DateTime.now());

  bool get messagesMuted => _active(messagesUntil);
  bool get callsMuted => _active(callsUntil);
  bool get anyMuted => messagesMuted || callsMuted;

  factory MutedUser.fromJson(Map<String, dynamic> json) => MutedUser(
        userId: (json['userId'] ?? '').toString(),
        messagesUntil: json['messagesUntil'] != null
            ? DateTime.tryParse(json['messagesUntil'].toString())?.toLocal()
            : null,
        callsUntil: json['callsUntil'] != null
            ? DateTime.tryParse(json['callsUntil'].toString())?.toLocal()
            : null,
      );
}

/// Account user, as returned by the backend's toSafeObject().
class UserModel {
  final String id;
  final String? email;
  final String displayName;
  final String username;
  // When the username was last changed (null = never). Drives the 30-day
  // change cooldown shown on the edit-profile screen.
  final DateTime? usernameChangedAt;
  final String? avatar;
  final String bio;
  final bool isOnline;
  final DateTime? lastSeenAt;
  // Privacy prefs (present on your own profile; default true).
  final bool showOnlineStatus;
  final bool showLastSeen;
  // When off, this device won't ring for incoming calls (server-side DND).
  final bool receiveCalls;
  // Per-user mute list (present on your OWN profile). Drives muted badges and
  // in-app suppression; the server enforces the actual silencing.
  final List<MutedUser> mutedUsers;

  const UserModel({
    required this.id,
    required this.displayName,
    required this.username,
    this.usernameChangedAt,
    this.email,
    this.avatar,
    this.bio = '',
    this.isOnline = false,
    this.lastSeenAt,
    this.showOnlineStatus = true,
    this.showLastSeen = true,
    this.receiveCalls = true,
    this.mutedUsers = const [],
  });

  /// This user's mute entry for [otherUserId], if any.
  MutedUser? muteFor(String otherUserId) {
    for (final m in mutedUsers) {
      if (m.userId == otherUserId) return m;
    }
    return null;
  }

  /// The next moment the username may be changed (null = changeable now).
  DateTime? get usernameChangeableAt =>
      usernameChangedAt?.add(const Duration(days: 30));

  /// Whether the username can be changed right now.
  bool get canChangeUsername {
    final at = usernameChangeableAt;
    return at == null || DateTime.now().isAfter(at);
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: (json['_id'] ?? json['id']).toString(),
      email: json['email'] as String?,
      displayName: json['displayName'] as String? ?? '',
      username: json['username'] as String? ?? '',
      usernameChangedAt: DateTime.tryParse('${json['usernameChangedAt'] ?? ''}'),
      avatar: json['avatar'] as String?,
      bio: json['bio'] as String? ?? '',
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeenAt: json['lastSeenAt'] != null
          ? DateTime.tryParse(json['lastSeenAt'].toString())
          : null,
      showOnlineStatus: json['showOnlineStatus'] as bool? ?? true,
      showLastSeen: json['showLastSeen'] as bool? ?? true,
      receiveCalls: json['receiveCalls'] as bool? ?? true,
      mutedUsers: (json['mutedUsers'] as List?)
              ?.map((m) => MutedUser.fromJson(Map<String, dynamic>.from(m as Map)))
              .toList() ??
          const [],
    );
  }
}
