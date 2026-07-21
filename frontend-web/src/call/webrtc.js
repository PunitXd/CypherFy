// Multi-peer WebRTC mesh, signalled over Socket.io — port of
// frontend/lib/services/webrtc_service.dart using native browser WebRTC.
//
// The server only relays SDP + ICE (backend webrtc.handler.js); media flows
// peer-to-peer, DTLS-SRTP encrypted. One RTCPeerConnection per remote peer
// (keyed by socket id), so a 1:1 DM is the N=1 case of a group call.
//
// Glare-free: whoever JOINS offers to every peer already present
// (connectToPeer initiator:true); existing peers answer the offer that arrives.

import { socketService } from '../socket/socket';

class WebRtcService {
  constructor() {
    this._localStream = null;
    this._peers = new Map(); // socketId -> RTCPeerConnection
    this._pending = new Map(); // socketId -> RTCIceCandidateInit[]
    this._iceServers = [{ urls: 'stun:stun.l.google.com:19302' }];
    this._callId = null;
    this._videoEnabled = false;

    this.onRemoteStream = null; // (socketId, MediaStream)
    this.onPeerLeft = null; // (socketId)
  }

  get localStream() {
    return this._localStream;
  }
  get videoEnabled() {
    return this._videoEnabled;
  }
  get peerIds() {
    return [...this._peers.keys()];
  }

  configure({ callId, iceServers }) {
    this._callId = callId;
    if (Array.isArray(iceServers) && iceServers.length) this._iceServers = iceServers;
  }

  async initLocalMedia({ video }) {
    this._videoEnabled = video;
    this._localStream = await navigator.mediaDevices.getUserMedia({
      audio: true,
      video: video ? { facingMode: 'user' } : false,
    });
  }

  _createPeer(socketId) {
    const pc = new RTCPeerConnection({ iceServers: this._iceServers });

    if (this._localStream) {
      for (const track of this._localStream.getTracks()) {
        pc.addTrack(track, this._localStream);
      }
    }

    pc.onicecandidate = (e) => {
      if (!e.candidate) return;
      socketService.emit('ice_candidate', {
        candidate: e.candidate.toJSON(),
        targetSocketId: socketId,
        callId: this._callId,
      });
    };
    pc.ontrack = (e) => {
      if (e.streams && e.streams[0]) this.onRemoteStream?.(socketId, e.streams[0]);
    };

    this._peers.set(socketId, pc);
    return pc;
  }

  // As the joiner (initiator) we send the offer; existing peers wait for it.
  async connectToPeer(socketId, { initiator }) {
    if (this._peers.has(socketId)) return;
    const pc = this._createPeer(socketId);
    if (initiator) {
      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      socketService.emit('webrtc_offer', {
        offer: { type: offer.type, sdp: offer.sdp },
        targetSocketId: socketId,
        callId: this._callId,
      });
    }
  }

  async handleOffer(fromSocketId, offer) {
    const pc = this._peers.get(fromSocketId) || this._createPeer(fromSocketId);
    await pc.setRemoteDescription(new RTCSessionDescription(offer));
    await this._drain(fromSocketId, pc);
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    socketService.emit('webrtc_answer', {
      answer: { type: answer.type, sdp: answer.sdp },
      targetSocketId: fromSocketId,
      callId: this._callId,
    });
  }

  async handleAnswer(fromSocketId, answer) {
    const pc = this._peers.get(fromSocketId);
    if (!pc) return;
    await pc.setRemoteDescription(new RTCSessionDescription(answer));
    await this._drain(fromSocketId, pc);
  }

  async handleCandidate(fromSocketId, cand) {
    if (!cand || !cand.candidate) return;
    const pc = this._peers.get(fromSocketId);
    // Buffer until the peer exists AND its remote description is set.
    if (!pc || !pc.remoteDescription) {
      if (!this._pending.has(fromSocketId)) this._pending.set(fromSocketId, []);
      this._pending.get(fromSocketId).push(cand);
      return;
    }
    await pc.addIceCandidate(new RTCIceCandidate(cand));
  }

  async _drain(socketId, pc) {
    const queued = this._pending.get(socketId);
    if (!queued) return;
    this._pending.delete(socketId);
    for (const c of queued) await pc.addIceCandidate(new RTCIceCandidate(c));
  }

  async removePeer(socketId) {
    const pc = this._peers.get(socketId);
    this._peers.delete(socketId);
    this._pending.delete(socketId);
    try {
      pc?.close();
    } catch {
      /* already closed */
    }
    this.onPeerLeft?.(socketId);
  }

  // ---- in-call controls ----
  toggleMic() {
    return this._toggle(this._localStream?.getAudioTracks());
  }
  toggleCamera() {
    return this._toggle(this._localStream?.getVideoTracks());
  }
  _toggle(tracks) {
    if (!tracks || !tracks.length) return false;
    const on = !tracks[0].enabled;
    for (const t of tracks) t.enabled = on;
    return on;
  }

  async endAll() {
    for (const pc of this._peers.values()) {
      try {
        pc.close();
      } catch {
        /* ignore */
      }
    }
    this._peers.clear();
    this._pending.clear();
    for (const t of this._localStream?.getTracks() ?? []) t.stop();
    this._localStream = null;
    this._callId = null;
    this._videoEnabled = false;
  }
}

export const webrtc = new WebRtcService();
