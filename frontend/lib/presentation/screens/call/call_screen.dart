import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../providers/auth_provider.dart';
import '../../providers/call_provider.dart';
import '../../widgets/common/app_avatar.dart';

/// The active-call surface: outgoing ringing, connecting, and connected states
/// for both 1:1 and group (mesh) calls, voice or video.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Repaint once a second so the call-duration label ticks.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _statusLine(CallState call) {
    switch (call.status) {
      case CallStatus.outgoing:
        return 'Ringing…';
      case CallStatus.connecting:
        return 'Connecting…';
      case CallStatus.connected:
        final started = call.startedAt;
        if (started == null) return 'Connected';
        final d = DateTime.now().difference(started);
        final mm = d.inMinutes.toString().padLeft(2, '0');
        final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
        return '$mm:$ss';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(callProvider);
    final notifier = ref.read(callProvider.notifier);
    final remotes = call.participants;
    final selfAvatar = ref.watch(authProvider).user?.avatar;
    final showVideoStage =
        call.isVideo && remotes.any((p) => p.hasVideo || p.renderer.srcObject != null);

    return Scaffold(
      backgroundColor: const Color(0xFF12100E),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // --- Stage: a WhatsApp-style participant grid for group calls; 1:1 keeps
          //     the full remote video or single-avatar layout. ---
          if (call.isGroup)
            _GroupStage(
              call: call,
              statusLine: _statusLine(call),
              selfAvatar: selfAvatar,
            )
          else if (showVideoStage)
            _VideoStage(participants: remotes)
          else
            _AvatarStage(call: call, statusLine: _statusLine(call)),

          // --- Local self-preview (video only; group shows self as a grid card) ---
          if (!call.isGroup &&
              call.isVideo &&
              call.localRenderer != null &&
              call.camOn)
            Positioned(
              top: 48,
              right: 16,
              width: 108,
              height: 156,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RTCVideoView(
                  call.localRenderer!,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),

          // --- Back / minimize: hide the call behind the chat (call keeps going) ---
          Positioned(
            top: 40,
            left: 4,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              // No tooltip: the call screen renders above the Navigator, so it
              // has no Overlay ancestor and a Tooltip throws "No Overlay found".
              onPressed: notifier.minimize,
            ),
          ),

          // --- Top: name + status while in the 1:1 video stage ---
          if (showVideoStage && !call.isGroup)
            Positioned(
              top: 48,
              left: 56,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    call.isGroup
                        ? 'Group call'
                        : (call.peerName ?? 'Call'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(_statusLine(call),
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),

          // --- Transient in-call notice (e.g. "Bob declined") — call continues ---
          if (call.flash != null)
            Positioned.fill(
              // Middle of the bottom half of the screen, horizontally centred.
              child: IgnorePointer(
                child: Align(
                  alignment: const Alignment(0, 0.5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      call.flash!,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ),
              ),
            ),

          // --- Controls ---
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: _Controls(call: call, notifier: notifier),
          ),

          // --- Call-waiting banner (a second call ringing in) ---
          if (call.waiting != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _WaitingBanner(waiting: call.waiting!, notifier: notifier),
            ),
        ],
      ),
    );
  }
}

class _WaitingBanner extends StatelessWidget {
  final PendingCall waiting;
  final CallNotifier notifier;
  const _WaitingBanner({required this.waiting, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2A2622),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              const Icon(Icons.phone_callback, color: Colors.white70, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      waiting.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Incoming ${waiting.isVideo ? 'video' : 'voice'} call',
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Decline the new call, stay in the current one.
              TextButton(
                onPressed: notifier.declineWaiting,
                child: const Text('Decline',
                    style: TextStyle(color: Color(0xFFE24B4A))),
              ),
              const SizedBox(width: 4),
              // End the current call and pick up the new one.
              ElevatedButton(
                onPressed: notifier.acceptWaiting,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D9E75),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('Accept'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarStage extends StatelessWidget {
  final CallState call;
  final String statusLine;
  const _AvatarStage({required this.call, required this.statusLine});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppAvatar(
            name: call.peerName ?? (call.isGroup ? 'Group' : 'Call'),
            imageUrl: call.peerAvatar,
            size: 120,
          ),
          const SizedBox(height: 24),
          Text(
            call.isGroup ? 'Group call' : (call.peerName ?? 'Call'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(statusLine,
              style: const TextStyle(color: Colors.white70, fontSize: 15)),
        ],
      ),
    );
  }
}

class _VideoStage extends StatelessWidget {
  final List<CallParticipant> participants;
  const _VideoStage({required this.participants});

  @override
  Widget build(BuildContext context) {
    final tiles = participants
        .map((p) => _RemoteTile(participant: p))
        .toList(growable: false);

    if (tiles.length <= 1) {
      return tiles.isEmpty ? const SizedBox.shrink() : tiles.first;
    }
    // Group: simple responsive grid.
    final cols = tiles.length <= 4 ? 2 : 3;
    return GridView.count(
      crossAxisCount: cols,
      padding: const EdgeInsets.only(top: 90, bottom: 120, left: 6, right: 6),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: tiles,
    );
  }
}

/// WhatsApp-style group-call layout: a header with the live participant count +
/// duration, and one card per person (self + every remote) showing their video
/// or avatar.
class _GroupStage extends StatelessWidget {
  final CallState call;
  final String statusLine;
  final String? selfAvatar;
  const _GroupStage({
    required this.call,
    required this.statusLine,
    this.selfAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final remotes = call.participants;
    final count = remotes.length + 1; // include self

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Column(
        children: [
          const Text('Group call',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            remotes.isEmpty
                ? (statusLine.isEmpty ? 'Waiting for others…' : statusLine)
                : '$count in call${statusLine.isEmpty ? '' : '  ·  $statusLine'}',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );

    Widget body;
    if (remotes.isEmpty) {
      // Just you so far (ringing / waiting for others) → a clean centered avatar,
      // not a single full-screen grid card.
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppAvatar(name: 'You', imageUrl: selfAvatar, size: 120),
            const SizedBox(height: 14),
            const Text('You',
                style: TextStyle(color: Colors.white70, fontSize: 15)),
          ],
        ),
      );
    } else {
      final cols = count <= 4 ? 2 : 3;
      final cards = <Widget>[
        _ParticipantCard(
          name: 'You',
          avatar: selfAvatar,
          renderer: call.isVideo && call.camOn ? call.localRenderer : null,
          mirror: true,
        ),
        ...remotes.map((p) => _ParticipantCard(
              name: p.name,
              avatar: p.avatar,
              renderer: p.hasVideo && p.renderer.srcObject != null
                  ? p.renderer
                  : null,
            )),
      ];
      body = GridView.count(
        crossAxisCount: cols,
        childAspectRatio: 0.82,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 120),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        children: cards,
      );
    }

    return SafeArea(
      child: Column(
        children: [header, Expanded(child: body)],
      ),
    );
  }
}

/// A single person's tile in the group grid — their video if live, else avatar,
/// with a name label.
class _ParticipantCard extends StatelessWidget {
  final String name;
  final String? avatar;
  final RTCVideoRenderer? renderer;
  final bool mirror;
  const _ParticipantCard({
    required this.name,
    this.avatar,
    this.renderer,
    this.mirror = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasVideo = renderer != null && renderer!.srcObject != null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: const Color(0xFF1E1A16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasVideo)
              RTCVideoView(
                renderer!,
                mirror: mirror,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              Center(child: AppAvatar(name: name, imageUrl: avatar, size: 72)),
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteTile extends StatelessWidget {
  final CallParticipant participant;
  const _RemoteTile({required this.participant});

  @override
  Widget build(BuildContext context) {
    final hasVideo =
        participant.hasVideo && participant.renderer.srcObject != null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        color: const Color(0xFF1E1A16),
        child: hasVideo
            ? RTCVideoView(
                participant.renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : Center(
                child: AppAvatar(name: participant.name, size: 72),
              ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final CallState call;
  final CallNotifier notifier;
  const _Controls({required this.call, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CtlButton(
          icon: call.micOn ? Icons.mic : Icons.mic_off,
          active: call.micOn,
          onTap: notifier.toggleMute,
        ),
        if (call.isVideo) ...[
          _CtlButton(
            icon: call.camOn ? Icons.videocam : Icons.videocam_off,
            active: call.camOn,
            onTap: notifier.toggleCamera,
          ),
          if (!kIsWeb)
            _CtlButton(
              icon: Icons.cameraswitch,
              active: true,
              onTap: notifier.switchCamera,
            ),
        ] else if (!kIsWeb)
          _CtlButton(
            icon: call.speakerOn ? Icons.volume_up : Icons.volume_down,
            active: call.speakerOn,
            onTap: notifier.toggleSpeaker,
          ),
        _CtlButton(
          icon: Icons.call_end,
          active: true,
          background: const Color(0xFFE24B4A),
          onTap: () {
            if (call.status == CallStatus.outgoing) {
              notifier.cancel();
            } else {
              notifier.hangUp();
            }
          },
        ),
      ],
    );
  }
}

class _CtlButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color? background;
  final VoidCallback onTap;

  const _CtlButton({
    required this.icon,
    required this.active,
    required this.onTap,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final bg = background ??
        (active ? Colors.white24 : Colors.white10);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(icon,
              color: active || background != null
                  ? Colors.white
                  : Colors.white54,
              size: 26),
        ),
      ),
    );
  }
}
