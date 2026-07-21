// Thin singleton wrapper around socket.io-client — mirrors
// frontend/lib/services/socket_service.dart.
//
// Account users pass their access token in the handshake auth; guests connect
// anonymously (allowed by the backend for ephemeral rooms).

import { io } from 'socket.io-client';
import { SOCKET_URL } from '../config';
import { tokenStore } from '../api/client';

class SocketService {
  constructor() {
    this._socket = null;
  }

  get id() {
    return this._socket?.id ?? null;
  }

  get connected() {
    return this._socket?.connected ?? false;
  }

  // Whether a socket object exists yet (may still be connecting). Used to decide
  // socket ownership: the shell opens it once, chats reuse it.
  get hasSocket() {
    return this._socket != null;
  }

  /** Connect (or reconnect), tearing down any existing socket so auth stays current. */
  connect() {
    this.disconnect();
    const token = tokenStore.access;
    this._socket = io(SOCKET_URL, {
      transports: ['websocket'],
      auth: token ? { token } : {},
    });
    return this._socket;
  }

  ensure() {
    if (!this._socket) this.connect();
    return this._socket;
  }

  on(event, handler) {
    this._socket?.on(event, handler);
  }

  onConnect(handler) {
    this._socket?.on('connect', handler);
  }

  off(event, handler) {
    this._socket?.off(event, handler);
  }

  emit(event, data, ack) {
    if (ack) this._socket?.emit(event, data ?? {}, ack);
    else this._socket?.emit(event, data ?? {});
  }

  disconnect() {
    this._socket?.disconnect();
    this._socket = null;
  }
}

export const socketService = new SocketService();
