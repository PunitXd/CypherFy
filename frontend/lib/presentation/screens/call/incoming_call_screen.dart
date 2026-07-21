import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/call_provider.dart';
import '../../widgets/common/app_avatar.dart';

/// Full-screen ring card shown when a call is coming in. Overlaid above every
/// route by CallOverlayHost.
class IncomingCallScreen extends ConsumerWidget {
  const IncomingCallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callProvider);
    final notifier = ref.read(callProvider.notifier);
    final kind = call.isVideo ? 'video' : 'voice';

    return Scaffold(
      backgroundColor: const Color(0xFF12100E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            children: [
              const Spacer(),
              AppAvatar(
                name: call.peerName ?? 'Someone',
                imageUrl: call.peerAvatar,
                size: 128,
              ),
              const SizedBox(height: 28),
              Text(
                call.peerName ?? 'Someone',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Incoming $kind call…',
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CircleAction(
                    color: const Color(0xFFE24B4A),
                    icon: Icons.call_end,
                    label: 'Decline',
                    onTap: notifier.reject,
                  ),
                  _CircleAction(
                    color: const Color(0xFF1D9E75),
                    icon: call.isVideo ? Icons.videocam : Icons.call,
                    label: 'Accept',
                    onTap: notifier.acceptIncoming,
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CircleAction({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}
