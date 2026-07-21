import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_text_styles.dart';

/// Plain-language explanation of how CypherFy protects messages.
class EncryptionInfoScreen extends StatelessWidget {
  const EncryptionInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.howEncryptionWorks)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Icon(Icons.shield_outlined, size: 48, color: AppColors.primary),
          const SizedBox(height: 16),
          Text('Encrypted on your device', style: AppTextStyles.heading),
          const SizedBox(height: 8),
          Text(
            'Every message and file is encrypted with AES‑256‑GCM right on your '
            'device before it ever leaves it. The key is derived from the room '
            'code (for ephemeral rooms) or the shared room identifier (for direct '
            'messages) — the server never receives it.',
            style: AppTextStyles.bodySecondary,
          ),
          const SizedBox(height: 24),
          const _Point(
            icon: Icons.cloud_off_outlined,
            title: 'The server only sees ciphertext',
            body:
                'CypherFy stores encrypted blobs and the random IV used to '
                'encrypt them. It never stores or logs your message text or files.',
          ),
          const _Point(
            icon: Icons.notifications_off_outlined,
            title: 'Content‑free notifications',
            body:
                'Push notifications and conversation previews never contain '
                'message content — only that something arrived.',
          ),
          const _Point(
            icon: Icons.timer_outlined,
            title: 'Ephemeral by design',
            body:
                'Ephemeral rooms and their messages are deleted automatically '
                'when the room expires. Nothing is kept.',
          ),
          const SizedBox(height: 16),
          Text(
            'Note: CypherFy uses a trusted‑server model — keys are derived from '
            'shared secrets rather than exchanged via per‑device key pairs. Treat '
            'room codes as the secret that protects a conversation.',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Point({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.subheading),
                const SizedBox(height: 4),
                Text(body, style: AppTextStyles.bodySecondary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
