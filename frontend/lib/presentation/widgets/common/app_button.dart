import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

/// Primary / secondary button with an optional loading state.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool secondary;
  final bool danger;
  final IconData? icon;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.secondary = false,
    this.danger = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    // Genuinely disabled = no handler AND not just mid-load. While loading we
    // keep the active fill (taps are swallowed by a no-op) so a busy button
    // never looks greyed-out.
    final isDisabled = onPressed == null && !loading;

    // On a light `primary` fill use dark ink; on the dark secondary fill use
    // light ink so the label/spinner stays legible. Dim the label when disabled.
    final Color fg = isDisabled
        ? AppColors.textMuted
        : (secondary ? AppColors.textPrimary : AppColors.onPrimary);

    final child = loading
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: secondary ? AppColors.textPrimary : AppColors.onPrimary,
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
              ],
              Text(label, style: AppTextStyles.button.copyWith(color: fg)),
            ],
          );

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? () {} : onPressed,
        style: secondary
            ? ElevatedButton.styleFrom(
                backgroundColor: AppColors.surfaceEl,
                foregroundColor: AppColors.textPrimary,
                disabledBackgroundColor: AppColors.surfaceContainerHigh,
                disabledForegroundColor: AppColors.textMuted,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: AppColors.border, width: 0.5),
                ),
              )
            : danger
                ? ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: AppColors.onPrimary,
                    disabledBackgroundColor: AppColors.surfaceContainerHigh,
                    disabledForegroundColor: AppColors.textMuted,
                  )
                : null,
        child: child,
      ),
    );
  }
}
