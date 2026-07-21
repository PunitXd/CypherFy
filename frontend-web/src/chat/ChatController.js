// Drives a single open chat: socket wiring, the room key, and the decrypted
// message list. Port of chat_provider.dart (ChatNotifier).
//
// Socket ownership: the AppShell opens ONE persistent socket after login; a chat
// reuses it (attaching/detaching its own room listeners and emitting join/leave).
// A standalone guest /room/:code link has no shell, so the controller opens its
// own socket (`_ownsSocket`) and closes it on dispose.
//
// Because a shared socket stays joined to previously-opened `perm:<id>` channels
// (there is no leave-permanent server event), inbound room events are filtered by
// the active room id so messages never bleed across conversations.

import { socketService } from '../socket/socket';
import { roomApi } from '../api/rooms';
import {
  deriveKeyFromCode,
  encryptText,
  decryptText,
  encryptFile,
  decryptFileBytes,
  decryptFileMeta,
} from '../crypto/crypto';

const INITIAL = {
  messages: [],
  typingAliases: [],
  members: [],
  connected: false,
  ended: false,
  expiringSecondsLeft: null,
  waitingForAdmission: false,
  rejected: false,
  knockRequests: [],
  errorMessage: null,
  roomName: null,
  expiresAt: null,
  // Ongoing group call in this ephemeral room (rejoin banner).
  groupCallId: null,
  groupCallType: null,
  groupCallCount: 0,
  groupCallStartedAt: null,
};

export class ChatController {
  constructor({ isEphemeral, code = null, roomId = null, myAlias = null, myUserId = null, isHost = false, isLocked = false, standalone = false }) {
    this.isEphemeral = isEphemeral;
    this.code = code;
    this.roomId = roomId;
    this.myAlias = myAlias;
    this.myUserId = myUserId;
    this.isHost = isHost;
    this.isLocked = isLocked;
    this.standalone = standalone; // guest /room/:code — owns + closes the socket

    this.state = INITIAL;
    this._listeners = new Set();
    this._key = null;
    this._foreground = true;
    this._activeRoomId = null;
    this._wired = false; // guard: async start() + StrictMode must not double-wire
    this._seen = new Set(); // synchronous dedupe of message ids

    this._typingActive = false;
    this._lastTypingSentAt = 0;
    this._typingStopTimer = null;
    this._typingTimers = new Map();
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

  get _target() {
    return this.isEphemeral ? { code: this.code } : { roomId: this.roomId };
  }
  _isOwn(m) {
    return this.isEphemeral ? m.senderAlias === this.myAlias : m.senderId === this.myUserId;
  }
  // True when an inbound room event belongs to a DIFFERENT room than this one.
  _foreign(roomId) {
    return this._activeRoomId && roomId != null && String(roomId) !== String(this._activeRoomId);
  }

  async start() {
    this._key = await deriveKeyFromCode(this.isEphemeral ? this.code : this.roomId);
    // Reuse the shell's persistent socket if present; otherwise open one.
    socketService.ensure();
    this._wire();
    if (socketService.connected) this._connectFlow();
    else socketService.onConnect(this._connectFlow);
  }

  _wire() {
    if (this._wired) return; // already listening — never stack handlers
    this._wired = true;
    socketService.on('room_joined', this._onRoomJoined);
    socketService.on('new_message', this._onNewMessage);
    socketService.on('message_deleted', this._onMessageDeleted);
    socketService.on('reaction_updated', this._onReaction);
    socketService.on('receipt_update', this._onReceiptUpdate);
    socketService.on('typing_update', this._onTyping);
    socketService.on('user_joined', this._onUserJoined);
    socketService.on('user_left', this._onUserLeft);
    socketService.on('room_expiring', this._onExpiring);
    socketService.on('room_ended', this._onEnded);
    socketService.on('room_expired', this._onEnded);
    socketService.on('knock_request', this._onKnockRequest);
    socketService.on('knock_admitted', this._onKnockAdmitted);
    socketService.on('knock_rejected', this._onKnockRejected);
    socketService.on('call:group_active', this._onGroupActive);
    socketService.on('call:group_ended', this._onGroupEnded);
    socketService.on('error', this._onServerError);
  }

  _connectFlow = () => {
    if (!this.isEphemeral) {
      socketService.emit('join_permanent', { roomId: this.roomId });
      return;
    }
    // Surface any ongoing group call so a rejoin banner can show.
    socketService.emit('call:group_state', { code: this.code });
    if (this.isLocked && !this.isHost) {
      socketService.emit('knock', { code: this.code, alias: this.myAlias });
      this._set({ waitingForAdmission: true });
    } else {
      socketService.emit('join_room', { code: this.code, alias: this.myAlias });
    }
  };

  async _decrypt(m) {
    try {
      if (m.type === 'file') {
        if (!m.encMeta || !m.metaIv) return m;
        const meta = await decryptFileMeta(m.encMeta, m.metaIv, this._key);
        return { ...m, fileName: meta.name, fileType: meta.type };
      }
      if (!m.ciphertext || !m.iv) return m;
      const text = await decryptText(m.ciphertext, m.iv, this._key);
      return { ...m, decryptedText: text };
    } catch {
      return { ...m, decryptedText: '⚠️ unable to decrypt' };
    }
  }

  _onRoomJoined = async (data) => {
    // Anchor the active room id for the bleed guard.
    this._activeRoomId = data?.room?.roomId ?? this.roomId ?? null;
    const raw = data?.messages ?? [];
    const decrypted = [];
    for (const r of raw) decrypted.push(await this._decrypt(normalize(r)));

    const seen = new Set();
    const members = [];
    for (const u of data?.users ?? []) {
      const alias = String(u.alias ?? '');
      if (!alias || seen.has(alias)) continue;
      seen.add(alias);
      members.push({ alias, socketId: u.socketId != null ? String(u.socketId) : null });
    }
    this._set({
      messages: decrypted,
      members,
      connected: true,
      roomName: data?.room?.name ?? this.state.roomName,
      expiresAt: data?.room?.expiresAt ?? null,
    });
    this._markSeen(this._foreground);
  };

  _onNewMessage = async (data) => {
    const m = normalize(data);
    if (this._foreign(m.roomId)) return; // belongs to another open channel
    // Synchronous guard — the decrypt below is async, so a plain list check would
    // let two rapid duplicate events both slip through before state updates.
    if (this._seen.has(m.messageId) || this.state.messages.some((e) => e.messageId === m.messageId)) return;
    this._seen.add(m.messageId);
    const dec = await this._decrypt(m);
    this._clearTypingFor(m.senderAlias);
    this._set({ messages: [...this.state.messages, dec] });
    if (!this._isOwn(dec)) this._markSeen(this._foreground);
  };

  _onMessageDeleted = (data) => {
    const id = String(data.messageId);
    if (!this.state.messages.some((m) => m.messageId === id)) return; // not ours
    this._set({ messages: this.state.messages.filter((m) => m.messageId !== id) });
  };

  _onReaction = (data) => {
    const id = String(data.messageId);
    if (!this.state.messages.some((m) => m.messageId === id)) return;
    const emoji = data.emoji;
    const count = Number(data.count);
    this._set({
      messages: this.state.messages.map((m) =>
        m.messageId === id ? { ...m, reactions: { ...m.reactions, [emoji]: count } } : m
      ),
    });
  };

  _onReceiptUpdate = (data) => {
    if (this._foreign(data?.roomId)) return;
    const by = String(data.by ?? '');
    const read = String(data.state) === 'read';
    const upToAt = new Date(data.upToAt);
    if (!by || Number.isNaN(upToAt.getTime())) return;
    let changed = false;
    const next = this.state.messages.map((m) => {
      if (
        m.senderAlias !== by &&
        new Date(m.createdAt) <= upToAt &&
        (read ? !m.readBy.includes(by) : !m.deliveredTo.includes(by))
      ) {
        changed = true;
        return {
          ...m,
          deliveredTo: m.deliveredTo.includes(by) ? m.deliveredTo : [...m.deliveredTo, by],
          readBy: read && !m.readBy.includes(by) ? [...m.readBy, by] : m.readBy,
        };
      }
      return m;
    });
    if (changed) this._set({ messages: next });
  };

  _onUserJoined = (data) => {
    const alias = String(data.alias ?? '');
    if (!alias || this.state.members.some((m) => m.alias === alias)) return;
    this._set({ members: [...this.state.members, { alias, socketId: null }] });
  };

  _onUserLeft = (data) => {
    const alias = String(data.alias ?? '');
    if (!alias || alias === this.myAlias) return;
    let removed = false;
    const next = [];
    for (const m of this.state.members) {
      if (!removed && m.alias === alias) { removed = true; continue; }
      next.push(m);
    }
    if (removed) this._set({ members: next });
  };

  _onExpiring = (d) => this._set({ expiringSecondsLeft: Number(d?.secondsLeft ?? 60) });
  _onEnded = () => this._set({ ended: true });
  _onServerError = (data) => this._set({ errorMessage: (data && data.message) || 'Something went wrong' });

  // ---- group call (ephemeral rejoin banner) ----
  _onGroupActive = (data) => {
    this._set({
      groupCallId: data?.callId ?? null,
      groupCallType: data?.callType ?? 'audio',
      groupCallCount: Number(data?.count ?? 1),
      groupCallStartedAt: data?.startedAt ? Number(data.startedAt) : null,
    });
  };
  _onGroupEnded = () => this._set({ groupCallId: null, groupCallType: null, groupCallCount: 0, groupCallStartedAt: null });

  // ---- knock ----
  _onKnockRequest = (data) => {
    const req = { alias: String(data.alias ?? 'Someone'), socketId: String(data.socketId ?? '') };
    if (this.state.knockRequests.some((k) => k.socketId === req.socketId)) return;
    this._set({ knockRequests: [...this.state.knockRequests, req] });
  };
  _onKnockAdmitted = () => {
    this._set({ waitingForAdmission: false });
    socketService.emit('join_room', { code: this.code, alias: this.myAlias });
  };
  _onKnockRejected = () => this._set({ waitingForAdmission: false, rejected: true });

  admit(socketId) { socketService.emit('admit_user', { knockSocketId: socketId, code: this.code }); this._removeKnock(socketId); }
  reject(socketId) { socketService.emit('reject_user', { knockSocketId: socketId, code: this.code }); this._removeKnock(socketId); }
  _removeKnock(socketId) { this._set({ knockRequests: this.state.knockRequests.filter((k) => k.socketId !== socketId) }); }

  // ---- receipts ----
  _markSeen(read) {
    let upToId = null;
    for (const m of this.state.messages) if (!this._isOwn(m)) upToId = m.messageId;
    if (!upToId) return;
    socketService.emit('message_seen', { ...this._target, upToId, state: read ? 'read' : 'delivered' });
  }
  setForeground(v) { this._foreground = v; if (v) this._markSeen(true); }
  clearError() { this._set({ errorMessage: null }); }

  // ---- outbound ----
  async sendText(plaintext, replyTo = null) {
    if (!plaintext.trim()) return;
    this.stopTyping();
    const enc = await encryptText(plaintext, this._key);
    socketService.emit('send_message', { ...this._target, ciphertext: enc.ct, iv: enc.iv, replyTo });
  }
  async sendFileBytes(bytes, name, mimeType, replyTo = null) {
    const enc = await encryptFile(bytes, name, mimeType, this._key);
    const put = await roomApi.presignedPut();
    await roomApi.uploadBytes(put.url, enc.cipherBytes);
    socketService.emit('send_file', {
      ...this._target, blobName: put.blobName, iv: enc.iv, encMeta: enc.encMeta, metaIv: enc.metaIv, size: enc.size, replyTo,
    });
  }
  async fetchFileBytes(m) {
    const { url } = await roomApi.presignedGet(m.blobName);
    const cipher = await roomApi.downloadBytes(url);
    return decryptFileBytes(cipher, m.iv, this._key);
  }
  react(messageId, emoji) { socketService.emit('add_reaction', { messageId, emoji }); }
  deleteMessage(messageId) { socketService.emit('delete_message', { messageId }); }
  endRoom() { if (this.isEphemeral && this.code) socketService.emit('end_room', { roomCode: this.code }); }
  leave() { if (this.isEphemeral && this.code) socketService.emit('leave_room', { roomCode: this.code }); }

  // ---- typing ----
  handleTyping(hasText) {
    if (!hasText) { this.stopTyping(); return; }
    const now = Date.now();
    if (!this._typingActive || now - this._lastTypingSentAt >= 1500) {
      this._typingActive = true;
      this._lastTypingSentAt = now;
      socketService.emit('typing_start', { ...this._target });
    }
    clearTimeout(this._typingStopTimer);
    this._typingStopTimer = setTimeout(() => this.stopTyping(), 2500);
  }
  stopTyping() {
    clearTimeout(this._typingStopTimer);
    this._typingStopTimer = null;
    if (this._typingActive) {
      this._typingActive = false;
      this._lastTypingSentAt = 0;
      socketService.emit('typing_stop', { ...this._target });
    }
  }
  _onTyping = (data) => {
    const alias = String(data.alias ?? '');
    const isTyping = Boolean(data.isTyping);
    if (!alias || alias === this.myAlias) return;
    clearTimeout(this._typingTimers.get(alias));
    this._typingTimers.delete(alias);
    if (isTyping) {
      if (!this.state.typingAliases.includes(alias)) {
        this._set({ typingAliases: [...this.state.typingAliases, alias] });
      }
      const t = setTimeout(() => {
        this._typingTimers.delete(alias);
        this._set({ typingAliases: this.state.typingAliases.filter((a) => a !== alias) });
      }, 4000);
      this._typingTimers.set(alias, t);
    } else {
      this._set({ typingAliases: this.state.typingAliases.filter((a) => a !== alias) });
    }
  };
  _clearTypingFor(alias) {
    clearTimeout(this._typingTimers.get(alias));
    this._typingTimers.delete(alias);
    if (this.state.typingAliases.includes(alias)) {
      this._set({ typingAliases: this.state.typingAliases.filter((a) => a !== alias) });
    }
  }

  // ---- teardown ----
  dispose() {
    // Remove only THIS chat's room listeners. Never blanket-off 'connect' — the
    // shell owns a persistent connect handler; drop only ours.
    for (const e of [
      'room_joined', 'new_message', 'message_deleted', 'reaction_updated',
      'receipt_update', 'typing_update', 'user_joined', 'user_left',
      'room_expiring', 'room_ended', 'room_expired', 'knock_request',
      'knock_admitted', 'knock_rejected', 'call:group_active', 'call:group_ended', 'error',
    ]) {
      socketService.off(e);
    }
    socketService.off('connect', this._connectFlow);
    // Leave the ephemeral channel so the shared socket doesn't linger in it.
    if (this.isEphemeral && this.code) socketService.emit('leave_room', { roomCode: this.code });
    this._wired = false;
    this._seen.clear();
    clearTimeout(this._typingStopTimer);
    for (const t of this._typingTimers.values()) clearTimeout(t);
    this._typingTimers.clear();
    // Only a standalone guest room owns the socket; the shell keeps it alive
    // across navigation and closes it on logout.
    if (this.standalone) socketService.disconnect();
  }
}

function normalize(json) {
  const reactions = {};
  const rr = json.reactions ?? {};
  for (const k of Object.keys(rr)) reactions[k] = Number(rr[k]);
  return {
    messageId: String(json.messageId ?? json._id),
    roomId: String(json.roomId ?? ''),
    type: json.type ?? 'text',
    senderAlias: json.senderAlias ?? 'Unknown',
    senderId: json.senderId != null ? String(json.senderId) : null,
    ciphertext: json.ciphertext ?? null,
    iv: json.iv ?? null,
    blobName: json.blobName ?? null,
    encMeta: json.encMeta ?? null,
    metaIv: json.metaIv ?? null,
    size: json.size ?? null,
    replyTo: json.replyTo != null ? String(json.replyTo) : null,
    reactions,
    deliveredTo: (json.deliveredTo ?? []).map(String),
    readBy: (json.readBy ?? []).map(String),
    createdAt: json.createdAt ?? new Date().toISOString(),
    decryptedText: null,
    fileName: null,
    fileType: null,
  };
}
