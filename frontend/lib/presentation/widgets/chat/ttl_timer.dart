import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

/// Live countdown to an ephemeral room's expiry, shown in the chat app bar.
/// Turns coral in the final 60 seconds.
class TtlTimer extends StatefulWidget {
  final DateTime expiresAt;
  const TtlTimer({super.key, required this.expiresAt});

  @override
  State<TtlTimer> createState() => _TtlTimerState();
}

class _TtlTimerState extends State<TtlTimer> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final diff = widget.expiresAt.difference(DateTime.now());
    if (mounted) {
      setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _label {
    final h = _remaining.inHours;
    final m = _remaining.inMinutes % 60;
    final s = _remaining.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final urgent = _remaining.inSeconds <= 60;
    final color = urgent ? AppColors.coral : AppColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 14, color: color),
        const SizedBox(width: 4),
        Text(_label, style: AppTextStyles.caption.copyWith(color: color)),
      ],
    );
  }
}
