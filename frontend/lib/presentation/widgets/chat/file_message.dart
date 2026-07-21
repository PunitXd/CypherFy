import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/message_model.dart';

/// Inline representation of an encrypted file message. Shows the decrypted file
/// name + size once metadata has been decrypted; tap to download & decrypt.
class FileMessage extends StatelessWidget {
  final MessageModel message;
  final VoidCallback? onTap;

  const FileMessage({super.key, required this.message, this.onTap});

  String get _sizeLabel {
    final bytes = message.size ?? 0;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final name = message.fileName ?? 'Encrypted file';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.insert_drive_file_outlined,
                color: AppColors.primaryLt, size: 20),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: AppTextStyles.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(_sizeLabel, style: AppTextStyles.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.download_outlined,
              color: AppColors.textSecondary, size: 18),
        ],
      ),
    );
  }
}
