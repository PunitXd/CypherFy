import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_text_styles.dart';

/// A horizontal rule with a centered "or" label, used to separate the primary
/// auth action from the Google sign-in option.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final line = Expanded(child: Divider(color: AppColors.border, thickness: 0.5));
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(AppStrings.orDivider, style: AppTextStyles.caption),
        ),
        line,
      ],
    );
  }
}
