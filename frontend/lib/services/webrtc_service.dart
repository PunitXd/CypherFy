import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'socket_service.dart';

/// Multi-peer WebRTC mesh, signalled over Socket.io.
///
/// The server only relays SDP + ICE (see backend webrtc.handler.js); media
/// flows peer-to-peer, DTLS-SRTP encrypted. One [RTCPeerConnection] is held per
/// remote participant (keyed by their socket id), so a 1:1 DM is simply the
/// N=1 case of a group call.
///
/// Mesh handshake is glare-free: whoever *joins* a call offers to every peer
/// already present ([connectToPeer] with `initiator: true`); existing peers
/// answer whatever offer arrives.
class WebRtcService {
  WebRtcService._();
  static final WebRtcService instance = WebRtcService._();

  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peers = {};
  // ICE candidates that arrived before the remote description was set.
  final Map<String, List<RTCIceCandidate>> _pending = {};

  List<Map<String, dynamic>> _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
  ];
  String? _callId;
  bool _videoEnabled = false;

  MediaStream? get localStream => _localStream;
  bool get videoEnabled => _videoEnabled;
  List<String> get peerIds => _peers.keys.toList();

  /// Wired by the call provider to render streams / react to a peer leaving.
  void Function(String socketId, MediaStream stream)? onRemoteStream;
  void Function(String socketId)? onPeerLeft;

  /// Provide the call id + ICE servers the server sent (call:started/accepted).
  void configure({required String callId, List<dynamic>? iceServers}) {
    _callId = callId;
    if (iceServers != null && iceServers.isNotEmpty) {
      _iceServers = iceServers
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
  }

  /// Acquire the local mic (and camera for video calls). Call once per call.
  Future<void> initLocalMedia({required bool video}) async {
    _videoEnabled = video;
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video ? {'facingMode': 'user'} : false,
    });
  }

  Future<RTCPeerConnection> _createPeer(String socketId) async {
    final pc = await createPeerConnection({
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    });

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    pc.onIceCandidate = (candidate) {
      SocketService.instance.emit('ice_candidate', {
        'candidate': candidate.toMap(),
        'targetSocketId': socketId,
        'callId': _callId,
      });
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        onRemoteStream?.call(socketId, event.streams.first);
      }
    };

    _peers[socketId] = pc;
    return pc;
  }

  /// Establish a connection to a peer. As the joiner ([initiator] true) we send
  /// the offer; existing peers wait for it.
  Future<void> connectToPeer(String socketId, {required bool initiator}) async {
    if (_peers.containsKey(socketId)) return;
    final pc = await _createPeer(socketId);
    if (initiator) {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      SocketService.instance.emit('webrtc_offer', {
        'offer': offer.toMap(),
        'targetSocketId': socketId,
        'callId': _callId,
      });
    }
  }

  Future<void> handleOffer(String fromSocketId, Map<String, dynamic> offer) async {
    final pc = _peers[fromSocketId] ?? await _createPeer(fromSocketId);
    await pc.setRemoteDescription(
      RTCSessionDescription(offer['sdp'] as String?, offer['type'] as String?),
    );
    await _drain(fromSocketId, pc);
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    SocketService.instance.emit('webrtc_answer', {
      'answer': answer.toMap(),
      'targetSocketId': fromSocketId,
      'callId': _callId,
    });
  }

  Future<void> handleAnswer(String fromSocketId, Map<String, dynamic> answer) async {
    final pc = _peers[fromSocketId];
    if (pc == null) return;
    await pc.setRemoteDescription(
      RTCSessionDescription(answer['sdp'] as String?, answer['type'] as String?),
    );
    await _drain(fromSocketId, pc);
  }

  Future<void> handleCandidate(String fromSocketId, Map<String, dynamic>? cand) async {
    if (cand == null || cand['candidate'] == null) return;
    final candidate = RTCIceCandidate(
      cand['candidate'] as String?,
      cand['sdpMid'] as String?,
      cand['sdpMLineIndex'] as int?,
    );
    final pc = _peers[fromSocketId];
    // Buffer until the peer exists AND its remote description is set.
    if (pc == null || (await pc.getRemoteDescription()) == null) {
      (_pending[fromSocketId] ??= []).add(candidate);
      return;
    }
    await pc.addCandidate(candidate);
  }

  Future<void> _drain(String socketId, RTCPeerConnection pc) async {
    final queued = _pending.remove(socketId);
    if (queued == null) return;
    for (final c in queued) {
      await pc.addCandidate(c);
    }
  }

  /// Tear down one peer (they left) without ending the whole call.
  Future<void> removePeer(String socketId) async {
    final pc = _peers.remove(socketId);
    _pending.remove(socketId);
    await pc?.close();
    onPeerLeft?.call(socketId);
  }

  // ---- In-call controls ----

  /// Toggle the mic; returns the new enabled state.
  bool toggleMic() => _toggle(_localStream?.getAudioTracks());

  /// Toggle the camera; returns the new enabled state.
  bool toggleCamera() => _toggle(_localStream?.getVideoTracks());

  bool _toggle(List<MediaStreamTrack>? tracks) {
    if (tracks == null || tracks.isEmpty) return false;
    final on = !(tracks.first.enabled);
    for (final t in tracks) {
      t.enabled = on;
    }
    return on;
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks();
    if (tracks != null && tracks.isNotEmpty) {
      await Helper.switchCamera(tracks.first);
    }
  }

  /// Route audio to the loudspeaker (mobile only; no-op/ignored on web).
  Future<void> setSpeakerphone(bool on) async {
    try {
      await Helper.setSpeakerphoneOn(on);
    } catch (_) {
      // Not supported on this platform.
    }
  }

  /// Tear the whole call down and release the camera/mic.
  Future<void> endAll() async {
    for (final pc in _peers.values) {
      await pc.close();
    }
    _peers.clear();
    _pending.clear();
    for (final t in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    _callId = null;
    _videoEnabled = false;
  }
}
