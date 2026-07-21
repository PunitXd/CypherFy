// User + chat-request REST — mirrors user.controller.js.
// Chat requests unlock permanent DMs: send → accept creates the room, both
// participants derive the key locally from the room id.

import { api, unwrap } from './client';

export const userApi = {
  // ---- profile ----
  async me() {
    return unwrap(await api.get('/users/me')).user;
  },
  async updateMe(patch) {
    return unwrap(await api.patch('/users/me', patch)).user;
  },

  // Upload a profile picture (multipart). Backend streams it to R2 and returns
  // the URL. Content-Type is left to the browser so the multipart boundary is set.
  async uploadAvatar(file) {
    const fd = new FormData();
    fd.append('avatar', file);
    return unwrap(await api.post('/upload/avatar', fd, { headers: { 'Content-Type': undefined } })); // { avatar }
  },
  async deleteAccount(password) {
    return unwrap(await api.delete('/users/me', { data: { password } }));
  },

  // ---- discovery ----
  async search(q) {
    return unwrap(await api.get('/users/search', { params: { q } })).users;
  },
  async profile(userId) {
    return unwrap(await api.get(`/users/${userId}`)); // { user, relationship }
  },

  // ---- contacts ----
  async contacts() {
    return unwrap(await api.get('/users/contacts')).contacts;
  },
  async addContact(userId) {
    return unwrap(await api.post(`/users/${userId}/contact`));
  },
  async removeContact(userId) {
    return unwrap(await api.delete(`/users/${userId}/contact`));
  },
  async setMute(userId, body) {
    return unwrap(await api.put(`/users/${userId}/mute`, body)).user;
  },

  // ---- chat requests ----
  async sendRequest(toUserId) {
    return unwrap(await api.post('/requests', { toUserId })).request;
  },
  async getRequests() {
    return unwrap(await api.get('/requests')); // { incoming, outgoing }
  },
  async acceptRequest(requestId) {
    return unwrap(await api.patch(`/requests/${requestId}/accept`)).room; // { _id, ... }
  },
  async rejectRequest(requestId) {
    return unwrap(await api.patch(`/requests/${requestId}/reject`));
  },
};
