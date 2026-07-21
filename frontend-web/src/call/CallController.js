// Orchestrates call signalling (Socket.io) + media (webrtc mesh). Singleton port
// of frontend/lib/.../call_provider.dart (CallNotifier), web-only (no CallKit,
// wakelock, or native permissions — the browser handles getUserMedia prompts).

import { webrtc } from './webrtc';
import { socketService } from '../socket/socket';
import { ringStart, ringStop, beepOnce } from './ring';

const IDLE = {
  status: 'idle', // idle | outgoing | incoming | connecting | connected | ended
  callId: null,
  callType: 'audio',
  isGroup: false,
  peerName: null,
  peerAvatar: null,
  micOn: true,
  camOn: true,
  startedAt: null,
  localStream: null,
  participants: [], // { socketId, userId, name, stream, hasVideo }
  note: null,
  waiting: null, // { callId, name, callType, isGroup }
  flash: null,
  minimized: false,
};

class CallController {
  constructor() {
    this.state = IDLE;
    this._listeners = new Set();
    this._peers = new Map();
    this._ringTimeout = null;
    this._flashTimer = null;
    this._wired = false;
    webrtc.onRemoteStream = this._onRemoteStream;
    webrtc.onPeerLeft = null;
  }

  subscribe = (fn) => {
    this._listeners.add(fn);
    return () => this._listeners.delete(fn);
  };
  getState = () => this.state;
  _set(patch) {
    this.state = { ...this.state, ...patch };
    this._listeners.forEach((l) => l(this.state));
  }

  get isActive() {
    return this.state.status !== 'idle' && this.state.status !== 'ended';
  }

  // ---- signalling wiring (idempotent; safe after reconnect) ----
  registerSignaling() {
    for (const e of [
      'call:incoming', 'call:started', 'call:accepted', 'call:peer_joined',
      'call:peer_left', 'call:rejected', 'call:peer_declined', 'call:cancelled',
      'call:ended', 'webrtc_offer', 'webrtc_answer', 'ice_candidate',
    ]) {
      socketService.off(e);
    }
    socketService.on('call:incoming', this._onIncoming);
    socketService.on('call:started', this._onStarted);
    socketService.on('call:accepted', this._onAccepted);
    socketService.on('call:peer_joined', this._onPeerJoined);
    socketService.on('call:peer_left', this._onPeerLeft);
    socketService.on('call:rejected', () => this._end({ note: 'Declined' }));
    socketService.on('call:peer_declined', this._onPeerDeclined);
    socketService.on('call:cancelled', () => this._end({}));
    socketService.on('call:ended', (data) =>
      this._end({ note: data?.reason === 'unavailable' ? 'User is unavailable' : null })
    );
    socketService.on('webrtc_offer', this._onOffer);
    socketService.on('webrtc_answer', this._onAnswer);
    socketService.on('ice_candidate', this._onCandidate);
    this._wired = true;
  }

  // ---- outgoing ----
  async startCall({ roomId, code, peerName, peerAvatar, video, isGroup = false }) {
    if (this.isActive) return;
    const callType = video ? 'video' : 'audio';
    this._set({
      ...IDLE,
      status: 'outgoing',
      callType,
      isGroup,
      peerName,
      peerAvatar,
      micOn: true,
      camOn: video,
    });
    if (!(await this._ensureLocalMedia(video))) {
      this._end({ note: 'Permission denied' });
      return;
    }
    socketService.emit('call:start', { ...(roomId ? { roomId } : {}), ...(code ? { code } : {}), callType });
    this._ringTimeout = setTimeout(() => {
      if (this.state.status === 'outgoing') this.cancel();
    }, 40000);
  }

  async acceptIncoming() {
    if (this.state.status !== 'incoming' || !this.state.callId) return;
    ringStop();
    const video = this.state.callType === 'video';
    if (!(await this._ensureLocalMedia(video))) {
      this.reject();
      return;
    }
    this._set({ status: 'connecting', camOn: video });
    socketService.emit('call:accept', { callId: this.state.callId });
  }

  async joinGroupCall({ callId, video, peerName = 'Group call' }) {
    if (this.isActive) return;
    this._set({
      ...IDLE,
      status: 'connecting',
      callId,
      callType: video ? 'video' : 'audio',
      isGroup: true,
      peerName,
      micOn: true,
      camOn: video,
    });
    if (!(await this._ensureLocalMedia(video))) {
      this._end({ note: 'Permission denied' });
      return;
    }
    socketService.emit('call:accept', { callId });
  }

  reject() {
    ringStop();
    if (this.state.callId) socketService.emit('call:reject', { callId: this.state.callId });
    this._end({});
  }
  cancel() {
    if (this.state.callId) socketService.emit('call:cancel', { callId: this.state.callId });
    this._end({ note: 'Cancelled' });
  }
  hangUp() {
    if (this.state.callId) socketService.emit('call:leave', { callId: this.state.callId });
    this._end({});
  }
  minimize() {
    this._set({ minimized: true });
  }
  returnToCall() {
    this._set({ minimized: false });
  }

  toggleMute() {
    this._set({ micOn: webrtc.toggleMic() });
  }
  toggleCamera() {
    this._set({ camOn: webrtc.toggleCamera() });
  }

  // ---- call-waiting ----
  async acceptWaiting() {
    const p = this.state.waiting;
    if (!p) return;
    ringStop();
    this.hangUp();
    this._set({
      ...IDLE,
      status: 'incoming',
      callId: p.callId,
      callType: p.callType,
      isGroup: p.isGroup,
      peerName: p.name,
    });
    await this.acceptIncoming();
  }
  declineWaiting() {
    const p = this.state.waiting;
    if (!p) return;
    socketService.emit('call:reject', { callId: p.callId });
    ringStop();
    this._set({ waiting: null });
  }

  // ---- signal handlers ----
  _onIncoming = (data) => {
    const from = data?.from ?? {};
    if (this.isActive) {
      if (this.state.waiting) {
        socketService.emit('call:reject', { callId: data.callId });
        return;
      }
      this._set({
        waiting: {
          callId: data.callId,
          name: from.name || 'Someone',
          avatar: from.avatar || null,
          callType: data.callType || 'audio',
          isGroup: data.isGroup === true,
        },
      });
      beepOnce();
      return;
    }
    this._set({
      ...IDLE,
      status: 'incoming',
      callId: data.callId,
      callType: data.callType || 'audio',
      isGroup: data.isGroup === true,
      peerName: from.name || 'Someone',
      peerAvatar: from.avatar || null,
    });
    ringStart();
  };

  _onStarted = (data) => {
    webrtc.configure({ callId: data.callId, iceServers: data.iceServers });
    this._set({ callId: data.callId });
  };

  _onAccepted = async (data) => {
    webrtc.configure({ callId: data.callId, iceServers: data.iceServers });
    this._set({ status: 'connecting' });
    for (const p of data.peers ?? []) {
      this._ensureParticipant(p.socketId, p.userId || '', p.name || 'Peer');
      await webrtc.connectToPeer(p.socketId, { initiator: true });
    }
  };

  _onPeerJoined = (data) => {
    clearTimeout(this._ringTimeout);
    const sid = data.socketId;
    const isNew = !this._peers.has(sid);
    this._ensureParticipant(sid, data.userId || '', data.name || 'Peer');
    if (this.state.status === 'outgoing') this._set({ status: 'connecting' });
    if (isNew) this._flash(`${data.name || 'Someone'} joined`);
  };

  _onPeerDeclined = (data) => {
    if (!this.isActive) return;
    this._flash(`${data?.name || 'Someone'} declined`);
  };

  _onPeerLeft = async (data) => {
    const sid = data?.socketId;
    if (!sid) return;
    await webrtc.removePeer(sid);
    this._peers.delete(sid);
    if (this._peers.size === 0) this.hangUp();
    else this._sync();
  };

  _onOffer = async (data) => {
    this._ensureParticipant(data.fromSocketId, '', 'Peer');
    await webrtc.handleOffer(data.fromSocketId, data.offer);
  };
  _onAnswer = async (data) => {
    await webrtc.handleAnswer(data.fromSocketId, data.answer);
  };
  _onCandidate = async (data) => {
    await webrtc.handleCandidate(data.fromSocketId, data.candidate || null);
  };

  _onRemoteStream = (socketId, stream) => {
    const p = this._ensureParticipant(socketId, '', 'Peer');
    p.stream = stream;
    p.hasVideo = stream.getVideoTracks().length > 0;
    this._set({
      status: 'connected',
      startedAt: this.state.startedAt ?? Date.now(),
    });
    this._sync();
  };

  // ---- helpers ----
  _ensureParticipant(socketId, userId, name) {
    let p = this._peers.get(socketId);
    if (p) return p;
    p = { socketId, userId, name, stream: null, hasVideo: false };
    this._peers.set(socketId, p);
    this._sync();
    return p;
  }

  async _ensureLocalMedia(video) {
    try {
      await webrtc.initLocalMedia({ video });
    } catch {
      return false;
    }
    this._set({ localStream: webrtc.localStream });
    return true;
  }

  _sync() {
    this._set({ participants: [...this._peers.values()] });
  }

  _flash(message) {
    this._set({ flash: message });
    clearTimeout(this._flashTimer);
    this._flashTimer = setTimeout(() => {
      if (this.state.flash) this._set({ flash: null });
    }, 3000);
  }

  async _end({ note }) {
    ringStop();
    clearTimeout(this._ringTimeout);
    this._ringTimeout = null;
    clearTimeout(this._flashTimer);
    this._flashTimer = null;
    await webrtc.endAll();
    this._peers.clear();
    if (note) {
      this._set({ ...IDLE, status: 'ended', note });
      setTimeout(() => {
        if (this.state.status === 'ended') this._set({ ...IDLE });
      }, 2000);
    } else {
      this._set({ ...IDLE });
    }
  }
}

export const callController = new CallController();
