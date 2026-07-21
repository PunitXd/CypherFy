/// A message as it travels on the wire — ALWAYS ciphertext for content.
///
/// `decryptedText` / `decryptedMeta` are filled in on the client after
/// decryption; they never come from the server.
class MessageModel {
  final String messageId;
  final String roomId;
  final String type; // 'text' | 'file'
  final String senderAlias;
  final String? senderId;

  // Text (encrypted)
  final String? ciphertext;
  final String? iv;

  // File (encrypted)
  final String? blobName;
  final String? encMeta;
  final String? metaIv;
  final int? size;

  final String? replyTo;
  final Map<String, int> reactions;
  // Read receipts: recipient identifiers (userId for DMs, alias for rooms) who
  // have received / read this message. readBy ⊆ deliveredTo. The sender isn't
  // listed. Drive the ✓ / ✓✓ / blue ✓✓ ticks on your own sent messages.
  final List<String> deliveredTo;
  final List<String> readBy;
  final DateTime createdAt;

  // ---- Client-side, post-decryption (not serialised to/from server) ----
  final String? decryptedText;
  final String? fileName;
  final String? fileType;

  const MessageModel({
    required this.messageId,
    required this.roomId,
    required this.type,
    required this.senderAlias,
    required this.createdAt,
    this.senderId,
    this.ciphertext,
    this.iv,
    this.blobName,
    this.encMeta,
    this.metaIv,
    this.size,
    this.replyTo,
    this.reactions = const {},
    this.deliveredTo = const [],
    this.readBy = const [],
    this.decryptedText,
    this.fileName,
    this.fileType,
  });

  bool get isFile => type == 'file';

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    final rawReactions = (json['reactions'] as Map?) ?? {};
    return MessageModel(
      messageId: (json['messageId'] ?? json['_id']).toString(),
      roomId: json['roomId'].toString(),
      type: json['type'] as String? ?? 'text',
      senderAlias: json['senderAlias'] as String? ?? 'Unknown',
      senderId: json['senderId']?.toString(),
      ciphertext: json['ciphertext'] as String?,
      iv: json['iv'] as String?,
      blobName: json['blobName'] as String?,
      encMeta: json['encMeta'] as String?,
      metaIv: json['metaIv'] as String?,
      size: json['size'] as int?,
      replyTo: json['replyTo']?.toString(),
      reactions: rawReactions
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
      deliveredTo: (json['deliveredTo'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      readBy:
          (json['readBy'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Return a copy with decrypted fields populated.
  MessageModel copyWithDecrypted({
    String? decryptedText,
    String? fileName,
    String? fileType,
    Map<String, int>? reactions,
  }) {
    return MessageModel(
      messageId: messageId,
      roomId: roomId,
      type: type,
      senderAlias: senderAlias,
      senderId: senderId,
      ciphertext: ciphertext,
      iv: iv,
      blobName: blobName,
      encMeta: encMeta,
      metaIv: metaIv,
      size: size,
      replyTo: replyTo,
      reactions: reactions ?? this.reactions,
      deliveredTo: deliveredTo,
      readBy: readBy,
      createdAt: createdAt,
      decryptedText: decryptedText ?? this.decryptedText,
      fileName: fileName ?? this.fileName,
      fileType: fileType ?? this.fileType,
    );
  }

  /// Copy with updated read-receipt lists, preserving decrypted content.
  MessageModel withReceipts({
    List<String>? deliveredTo,
    List<String>? readBy,
  }) {
    return MessageModel(
      messageId: messageId,
      roomId: roomId,
      type: type,
      senderAlias: senderAlias,
      senderId: senderId,
      ciphertext: ciphertext,
      iv: iv,
      blobName: blobName,
      encMeta: encMeta,
      metaIv: metaIv,
      size: size,
      replyTo: replyTo,
      reactions: reactions,
      deliveredTo: deliveredTo ?? this.deliveredTo,
      readBy: readBy ?? this.readBy,
      createdAt: createdAt,
      decryptedText: decryptedText,
      fileName: fileName,
      fileType: fileType,
    );
  }
}
