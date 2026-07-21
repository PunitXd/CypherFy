// Room REST + encrypted-file transfer — mirrors
// frontend/lib/data/repositories/room_repository.dart.

import axios from 'axios';
import { api, unwrap } from './client';

// A bare axios (no auth interceptor) for talking DIRECTLY to R2 via presigned
// URLs — an Authorization header would make R2 reject the request.
const r2 = axios.create();

export const roomApi = {
  // Ephemeral room create (public — guests allowed).
  async createEphemeral({ alias, name, maxUsers, ttlSeconds, isLocked = false, passHint = null }) {
    return unwrap(
      await api.post('/rooms', {
        createdBy: alias,
        name,
        maxUsers,
        ttlSeconds,
        isLocked,
        passHint,
      })
    ); // { roomId, code, name, maxUsers, isLocked, expiresAt }
  },

  // Validate an ephemeral code before joining (throws if not found/expired).
  async validateCode(code) {
    return unwrap(await api.get(`/rooms/${code}`)); // { roomId, code, name, maxUsers, isLocked, passHint, currentCount, expiresAt }
  },

  // The current user's permanent DM rooms (auth).
  async getPermanentRooms() {
    return unwrap(await api.get('/rooms/permanent')).rooms;
  },

  async deletePermanent(roomId) {
    return unwrap(await api.delete(`/rooms/permanent/${roomId}`));
  },

  // ---- Encrypted file transfer ----
  async presignedPut(blobName) {
    return unwrap(
      await api.get('/upload/presigned-put', { params: blobName ? { blobName } : {} })
    ); // { url, blobName, expiresIn }
  },

  async presignedGet(blobName) {
    return unwrap(await api.get('/upload/presigned-get', { params: { blobName } })); // { url }
  },

  // PUT encrypted bytes straight to R2.
  async uploadBytes(url, bytes) {
    await r2.put(url, bytes, { headers: { 'Content-Type': 'application/octet-stream' } });
  },

  // GET encrypted bytes back from R2.
  async downloadBytes(url) {
    const res = await r2.get(url, { responseType: 'arraybuffer' });
    return new Uint8Array(res.data);
  },
};
