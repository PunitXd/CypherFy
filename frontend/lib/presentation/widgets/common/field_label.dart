import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

/// Uppercase mono-style form-section label, optionally with a right-aligned
/// value (e.g. "Max Participants … 2 members"). Mirrors the Stitch form labels.
class FieldLabel extends StatelessWidget {
  final String text;
  final String? trailing;

  const FieldLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text.toUpperCase(),
      style: AppTextStyles.monoLabel.copyWith(
        color: AppColors.textSecondary,
        letterSpacing: 1.5,
      ),
    );

    if (trailing == null) return label;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        label,
        Text(
          trailing!,
          style: AppTextStyles.bodySecondary.copyWith(color: AppColors.primary),
        ),
      ],
    );
  }
}
