import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/room_model.dart';
import 'api_client.dart';

/// Room REST calls (ephemeral create/validate, permanent list/delete) and the
/// presigned-URL helpers for encrypted file transfer.
class RoomRepository {
  final ApiClient _api = ApiClient.instance;

  // A clean Dio for talking DIRECTLY to R2 via presigned URLs — no auth
  // interceptor (the presigned URL carries its own signature; an Authorization
  // header would make R2 reject the request).
  final Dio _r2 = Dio();

  /// Create an ephemeral room; returns the room (with code + expiry).
  Future<RoomModel> createEphemeral({
    required String alias,
    required String name,
    required int maxUsers,
    required int ttlSeconds,
    bool isLocked = false,
    String? passHint,
  }) async {
    final res = await _api.dio.post('/rooms', data: {
      'createdBy': alias,
      'name': name,
      'maxUsers': maxUsers,
      'ttlSeconds': ttlSeconds,
      'isLocked': isLocked,
      'passHint': passHint,
    });
    return RoomModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  /// Validate a code before joining; throws if not found/expired.
  Future<RoomModel> validateCode(String code) async {
    final res = await _api.dio.get('/rooms/$code');
    return RoomModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  /// List the current user's permanent DM rooms.
  Future<List<RoomModel>> getPermanentRooms() async {
    final res = await _api.dio.get('/rooms/permanent');
    final rooms = (res.data['data']['rooms'] as List)
        .map((r) => RoomModel.fromJson(r as Map<String, dynamic>))
        .toList();
    return rooms;
  }

  /// Delete a conversation on the current user's side only.
  Future<void> deletePermanent(String roomId) async {
    await _api.dio.delete('/rooms/permanent/$roomId');
  }

  // ---- Encrypted file transfer ---------------------------------------

  /// Get a short-lived presigned PUT URL + the object key to upload to.
  Future<({String url, String blobName})> presignedPut([String? blobName]) async {
    final res = await _api.dio.get('/upload/presigned-put', queryParameters: {
      if (blobName != null) 'blobName': blobName,
    });
    final data = res.data['data'] as Map<String, dynamic>;
    return (url: data['url'] as String, blobName: data['blobName'] as String);
  }

  /// Get a presigned GET URL to download an encrypted blob.
  Future<String> presignedGet(String blobName) async {
    final res = await _api.dio.get('/upload/presigned-get', queryParameters: {
      'blobName': blobName,
    });
    return res.data['data']['url'] as String;
  }

  /// PUT encrypted bytes straight to R2 using a presigned URL.
  Future<void> uploadBytes(String presignedUrl, Uint8List bytes) async {
    await _r2.put(
      presignedUrl,
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {Headers.contentLengthHeader: bytes.length},
        contentType: 'application/octet-stream',
      ),
    );
  }

  /// GET encrypted bytes back from R2 using a presigned URL.
  Future<Uint8List> downloadBytes(String presignedUrl) async {
    final res = await _r2.get<List<int>>(
      presignedUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const []);
  }
}
