import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

/// A single option in a [SelectPillGroup].
class SelectPillOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  const SelectPillOption({required this.value, required this.label, this.icon});
}

/// A wrap of pill-shaped single-select buttons — the selected pill is tinted
/// with the brand colour, the rest are outlined. Mirrors the Stitch pill
/// groups (max participants, auto-delete).
class SelectPillGroup<T> extends StatelessWidget {
  final T value;
  final List<SelectPillOption<T>> options;
  final ValueChanged<T> onChanged;

  const SelectPillGroup({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final opt in options)
          _Pill(
            label: opt.label,
            icon: opt.icon,
            selected: opt.value == value,
            onTap: () => onChanged(opt.value),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.primary : AppColors.textPrimary;
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 1 : 0.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: AppTextStyles.label.copyWith(color: fg)),
              if (icon != null) ...[
                const SizedBox(width: 4),
                Icon(icon, size: 14, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
