import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/user_model.dart';
import 'api_client.dart';

/// User + contacts + chat-request REST calls.
class UserRepository {
  final ApiClient _api = ApiClient.instance;

  /// The current user (used to refresh after an avatar upload).
  Future<UserModel> getMe() async {
    final res = await _api.dio.get('/users/me');
    return UserModel.fromJson(res.data['data']['user']);
  }

  Future<UserModel> updateProfile({
    String? displayName,
    String? bio,
    String? username,
  }) async {
    final res = await _api.dio.patch('/users/me', data: {
      if (displayName != null) 'displayName': displayName,
      if (bio != null) 'bio': bio,
      if (username != null) 'username': username,
    });
    return UserModel.fromJson(res.data['data']['user']);
  }

  /// Update privacy / notification preferences; returns the refreshed user.
  Future<UserModel> updatePrivacy({
    bool? showOnlineStatus,
    bool? showLastSeen,
    bool? receiveCalls,
  }) async {
    final res = await _api.dio.patch('/users/me', data: {
      if (showOnlineStatus != null) 'showOnlineStatus': showOnlineStatus,
      if (showLastSeen != null) 'showLastSeen': showLastSeen,
      if (receiveCalls != null) 'receiveCalls': receiveCalls,
    });
    return UserModel.fromJson(res.data['data']['user']);
  }

  /// Permanently delete the account (password-confirmed, full hard delete).
  Future<void> deleteAccount(String password) async {
    await _api.dio.delete('/users/me', data: {'password': password});
  }

  Future<List<UserModel>> search(String query) async {
    final res = await _api.dio.get('/users/search', queryParameters: {'q': query});
    return (res.data['data']['users'] as List)
        .map((u) => UserModel.fromJson(u as Map<String, dynamic>))
        .toList();
  }

  Future<UserModel> getProfile(String userId) async {
    final res = await _api.dio.get('/users/$userId');
    return UserModel.fromJson(res.data['data']['user']);
  }

  /// Fetch a profile together with the viewer's relationship to them, which
  /// drives the action button (Message / Accept / Request sent / Send request).
  Future<ProfileWithRelationship> getProfileWithRelationship(
    String userId,
  ) async {
    final res = await _api.dio.get('/users/$userId');
    final data = res.data['data'] as Map<String, dynamic>;
    final rel = (data['relationship'] as Map?) ?? const {};
    DateTime? parseUntil(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    return ProfileWithRelationship(
      user: UserModel.fromJson(data['user'] as Map<String, dynamic>),
      isSelf: rel['isSelf'] as bool? ?? false,
      isContact: rel['isContact'] as bool? ?? false,
      roomId: rel['roomId']?.toString(),
      incomingRequestId: rel['incomingRequestId']?.toString(),
      outgoingPending: rel['outgoingPending'] as bool? ?? false,
      messagesMutedUntil: parseUntil(rel['messagesMutedUntil']),
      callsMutedUntil: parseUntil(rel['callsMutedUntil']),
    );
  }

  /// Set or clear a per-user mute. Pass [messages]/[calls] to change that scope:
  /// a future DateTime mutes until then, [muteIndefinite] mutes until turned off,
  /// and null (with the flag) unmutes. Scopes left as `false` are unchanged.
  /// Returns the caller's refreshed profile (with the updated mute list).
  Future<UserModel> setMute(
    String userId, {
    bool updateMessages = false,
    DateTime? messagesUntil,
    bool updateCalls = false,
    DateTime? callsUntil,
  }) async {
    final body = <String, dynamic>{};
    if (updateMessages) {
      body['messagesUntil'] = messagesUntil?.millisecondsSinceEpoch;
    }
    if (updateCalls) {
      body['callsUntil'] = callsUntil?.millisecondsSinceEpoch;
    }
    final res = await _api.dio.put('/users/$userId/mute', data: body);
    return UserModel.fromJson(res.data['data']['user'] as Map<String, dynamic>);
  }

  Future<List<UserModel>> getContacts() async {
    final res = await _api.dio.get('/users/contacts');
    return (res.data['data']['contacts'] as List)
        .map((u) => UserModel.fromJson(u as Map<String, dynamic>))
        .toList();
  }

  Future<void> addContact(String userId) async {
    await _api.dio.post('/users/$userId/contact');
  }

  Future<void> removeContact(String userId) async {
    await _api.dio.delete('/users/$userId/contact');
  }

  /// Upload a profile picture (multipart) and return its public URL. Works on
  /// mobile and web — the caller passes the picked bytes + name + mime type.
  Future<String> uploadAvatar(
    Uint8List bytes,
    String filename,
    String? mimeType,
  ) async {
    final mt = (mimeType != null && mimeType.startsWith('image/'))
        ? mimeType
        : 'image/jpeg';
    final form = FormData.fromMap({
      'avatar': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType.parse(mt),
      ),
    });
    final res = await _api.dio.post('/upload/avatar', data: form);
    return res.data['data']['avatar'] as String;
  }

  // ---- Chat requests --------------------------------------------------

  Future<void> sendChatRequest(String toUserId) async {
    await _api.dio.post('/requests', data: {'toUserId': toUserId});
  }

  Future<Map<String, dynamic>> getChatRequests() async {
    final res = await _api.dio.get('/requests');
    return res.data['data'] as Map<String, dynamic>;
  }

  /// Accept a request. No key material is exchanged — both users derive the DM
  /// key from the returned room id via PBKDF2. Returns the created room's id.
  Future<String> acceptChatRequest(String requestId) async {
    final res = await _api.dio.patch('/requests/$requestId/accept');
    return res.data['data']['room']['_id'].toString();
  }

  Future<void> rejectChatRequest(String requestId) async {
    await _api.dio.patch('/requests/$requestId/reject');
  }
}

/// A user's public profile plus the viewer's relationship to them.
class ProfileWithRelationship {
  final UserModel user;
  final bool isSelf;
  final bool isContact; // accepted → show "Message"
  final String? roomId; // DM room id when isContact
  final String? incomingRequestId; // pending request they sent me → "Accept"
  final bool outgoingPending; // I sent them a request → "Request sent"
  // The viewer's mute state for this user (null/past = not muted).
  final DateTime? messagesMutedUntil;
  final DateTime? callsMutedUntil;

  const ProfileWithRelationship({
    required this.user,
    required this.isSelf,
    required this.isContact,
    this.roomId,
    this.incomingRequestId,
    this.outgoingPending = false,
    this.messagesMutedUntil,
    this.callsMutedUntil,
  });

  static bool _active(DateTime? until) =>
      until != null && until.isAfter(DateTime.now());
  bool get messagesMuted => _active(messagesMutedUntil);
  bool get callsMuted => _active(callsMutedUntil);

  /// Copy with both mute timestamps replaced (used for optimistic UI updates).
  ProfileWithRelationship withMute({
    required DateTime? messagesUntil,
    required DateTime? callsUntil,
  }) =>
      ProfileWithRelationship(
        user: user,
        isSelf: isSelf,
        isContact: isContact,
        roomId: roomId,
        incomingRequestId: incomingRequestId,
        outgoingPending: outgoingPending,
        messagesMutedUntil: messagesUntil,
        callsMutedUntil: callsUntil,
      );
}
