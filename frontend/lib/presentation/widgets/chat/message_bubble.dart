import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/message_model.dart';
import 'file_message.dart';

/// WhatsApp-style delivery state for one of your own sent messages.
enum MessageStatus { sent, delivered, read }

/// A single chat bubble. `isMine` right-aligns with a brand-tinted border;
/// others are left-aligned behind a small alias avatar with the sender's colour.
class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final Color senderColor;
  final bool showSender;
  final VoidCallback? onReact;
  final VoidCallback? onLongPress;
  final VoidCallback? onFileTap; // download+decrypt when a file bubble is tapped
  final MessageStatus? status; // receipt state, only for your own messages

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.senderColor,
    this.showSender = true,
    this.onReact,
    this.onLongPress,
    this.onFileTap,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: isMine ? _buildMine(context) : _buildOther(context),
    );
  }

  Widget _buildMine(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _bubble(context, border: AppColors.primary, tailRight: true),
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _time(),
              const SizedBox(width: 4),
              _statusTick(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOther(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Alias avatar chip.
        if (showSender)
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(right: 8, bottom: 20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: senderColor.withValues(alpha: 0.20),
            ),
            alignment: Alignment.center,
            child: Text(
              _initial,
              style: AppTextStyles.caption
                  .copyWith(color: senderColor, fontWeight: FontWeight.w600),
            ),
          )
        else
          const SizedBox(width: 32),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showSender)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Text(
                    message.senderAlias,
                    style: AppTextStyles.caption.copyWith(color: senderColor),
                  ),
                ),
              _bubble(context, border: AppColors.border, tailRight: false),
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 4),
                child: _time(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bubble(BuildContext context,
      {required Color border, required bool tailRight}) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: border, width: 0.5),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(tailRight ? 12 : 3),
            bottomRight: Radius.circular(tailRight ? 3 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            message.isFile
                ? FileMessage(message: message, onTap: onFileTap)
                : Text(message.decryptedText ?? '…', style: AppTextStyles.body),
            if (message.reactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  message.reactions.entries
                      .map((e) => '${e.key}${e.value}')
                      .join('  '),
                  style: AppTextStyles.caption,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _time() => Text(
        DateFormat.Hm().format(message.createdAt.toLocal()),
        style: AppTextStyles.monoLabel
            .copyWith(fontSize: 10, color: AppColors.textMuted),
      );

  // Read-receipt tick: single ✓ = sent, double ✓✓ = delivered (grey),
  // double ✓✓ blue = read (by all, in a group).
  static const _readBlue = Color(0xFF4FC3F7);
  Widget _statusTick() {
    switch (status) {
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 15, color: _readBlue);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: 15, color: AppColors.textMuted);
      case MessageStatus.sent:
      case null:
        return Icon(Icons.done, size: 15, color: AppColors.textMuted);
    }
  }

  String get _initial => message.senderAlias.isEmpty
      ? '?'
      : message.senderAlias.characters.first.toUpperCase();
}
