import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/call_provider.dart';
import '../../screens/call/call_screen.dart';
import '../../screens/call/incoming_call_screen.dart';

/// Mounted once at the app root (above the router). Renders the incoming/active
/// call UI over whatever screen is showing, so a call rings and connects from
/// anywhere in the app. Renders nothing (and blocks nothing) when idle.
class CallOverlayHost extends ConsumerWidget {
  const CallOverlayHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(callProvider.select((c) => c.status));
    final note = ref.watch(callProvider.select((c) => c.note));
    final minimized = ref.watch(callProvider.select((c) => c.minimized));

    switch (status) {
      case CallStatus.incoming:
        return const IncomingCallScreen();
      case CallStatus.outgoing:
      case CallStatus.connecting:
      case CallStatus.connected:
        // Minimized → reveal the chat underneath; its "tap to return" banner
        // brings the call back. The call itself keeps running.
        return minimized ? const SizedBox.shrink() : const CallScreen();
      case CallStatus.ended:
        if (note == null) return const SizedBox.shrink();
        // Brief, non-blocking end reason ("Declined" / "Busy" / "No answer").
        return IgnorePointer(
          child: SizedBox.expand(
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(note,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
              ),
            ),
          ),
        );
      case CallStatus.idle:
        return const SizedBox.shrink();
    }
  }
}
