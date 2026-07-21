import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

/// Circular avatar. Shows a network image when available, otherwise the first
/// initial on a deterministic colour. Optional online dot.
class AppAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double size;
  final bool showOnlineDot;
  final bool isOnline;

  const AppAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 40,
    this.showOnlineDot = false,
    this.isOnline = false,
  });

  @override
  Widget build(BuildContext context) {
    // Deterministic colour from the name so a user keeps the same tint.
    final color = AppColors.aliasColors[
        name.isEmpty ? 0 : name.codeUnitAt(0) % AppColors.aliasColors.length];
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    final avatar = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => _initialBox(color, initial),
                errorWidget: (_, __, ___) => _initialBox(color, initial),
              )
            : _initialBox(color, initial),
      ),
    );

    if (!showOnlineDot) return avatar;

    return Stack(
      children: [
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: size * 0.28,
            height: size * 0.28,
            decoration: BoxDecoration(
              color: isOnline ? AppColors.teal : AppColors.textMuted,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.bg, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _initialBox(Color color, String initial) {
    return Container(
      color: color.withValues(alpha: 0.25),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTextStyles.subheading.copyWith(color: color),
      ),
    );
  }
}
