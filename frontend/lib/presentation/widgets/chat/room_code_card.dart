import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_text_styles.dart';

/// Displays a freshly created room's 6-char code with copy + QR actions.
///
/// The code is the ONLY thing shared. Each participant derives the encryption
/// key from this code locally (PBKDF2) — no key or URL is ever shared.
class RoomCodeCard extends StatefulWidget {
  final String code;

  /// When the room auto-deletes; used to render the "Expires in …" pill.
  final DateTime? expiresAt;

  /// Heading/subheading above the code. Default to the just-created copy; the
  /// Room Detail page overrides these (the room isn't "created" there).
  final String heading;
  final String subheading;

  const RoomCodeCard({
    super.key,
    required this.code,
    this.expiresAt,
    this.heading = 'Room created',
    this.subheading = 'Share this code to invite people',
  });

  @override
  State<RoomCodeCard> createState() => _RoomCodeCardState();
}

class _RoomCodeCardState extends State<RoomCodeCard> {
  bool _showQr = false;

  String? get _expiryLabel {
    final exp = widget.expiresAt;
    if (exp == null) return null;
    final d = exp.difference(DateTime.now());
    if (d.isNegative) return 'Expired';
    if (d.inHours >= 24) return 'Expires in ${d.inDays}d';
    if (d.inHours >= 1) return 'Expires in ${d.inHours}h';
    return 'Expires in ${d.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header: key icon, title, subtitle.
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surfaceContainerHigh,
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Icon(Icons.vpn_key, color: AppColors.primary, size: 24),
        ),
        const SizedBox(height: 16),
        Text(widget.heading, style: AppTextStyles.heading),
        const SizedBox(height: 4),
        Text(widget.subheading, style: AppTextStyles.bodySecondary),
        const SizedBox(height: 24),

        // Prominent code display card.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Column(
            children: [
              Text(
                widget.code,
                style: AppTextStyles.code.copyWith(
                  fontSize: 32,
                  color: AppColors.primary,
                  letterSpacing: 8,
                ),
              ),
              if (_expiryLabel != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        _expiryLabel!.toUpperCase(),
                        style: AppTextStyles.monoLabel.copyWith(
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        if (_showQr) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            // QR encodes just the code string — not a URL.
            child: QrImageView(data: widget.code, size: 180),
          ),
          const SizedBox(height: 24),
        ],

        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  // Copy just the 6-char code.
                  await Clipboard.setData(ClipboardData(text: widget.code));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied')),
                    );
                  }
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy code'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _showQr = !_showQr),
                icon: const Icon(Icons.qr_code, size: 16),
                label: const Text(AppStrings.showQr),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Footer note.
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Anyone with this code can join the room',
                  style: AppTextStyles.caption,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
