// Auth REST calls — mirrors frontend/lib/data/repositories/auth_repository.dart.
// Endpoint/response shapes match backend/src/controllers/auth.controller.js.

import { api, tokenStore, unwrap } from './client';

export const authApi = {
  // Register → backend emails a verification OTP and grants no tokens yet.
  async register({ email, password, displayName, username }) {
    return unwrap(
      await api.post('/auth/register', { email, password, displayName, username })
    );
  },

  // Confirm the emailed OTP → verified + session tokens (same shape as login).
  async verifyEmail({ email, otp }) {
    const d = unwrap(await api.post('/auth/verify-email', { email, otp }));
    tokenStore.save(d.accessToken, d.refreshToken);
    return d; // { user, accessToken, refreshToken }
  },

  async resendVerification(email) {
    return unwrap(await api.post('/auth/resend-verification', { email }));
  },

  async login({ email, password }) {
    const d = unwrap(await api.post('/auth/login', { email, password }));
    tokenStore.save(d.accessToken, d.refreshToken);
    return d; // { user, accessToken, refreshToken }
  },

  // Exchange a Firebase ID token (Google) for our own session tokens.
  async firebase(idToken) {
    const d = unwrap(await api.post('/auth/firebase', { idToken }));
    tokenStore.save(d.accessToken, d.refreshToken);
    return d;
  },

  async forgotPassword(email) {
    return unwrap(await api.post('/auth/forgot-password', { email }));
  },

  // Verify a reset OTP → returns a one-time ticket for resetPassword's `token`.
  async verifyOtp({ email, otp }) {
    return unwrap(await api.post('/auth/verify-otp', { email, otp })); // { ticket }
  },

  // `token` is either the verify-otp ticket (in-app) or the emailed link token.
  async resetPassword({ email, token, newPassword }) {
    return unwrap(
      await api.post('/auth/reset-password', { email, token, newPassword })
    );
  },

  async me() {
    return unwrap(await api.get('/users/me')).user;
  },

  // Change password while logged in (sends the current refresh token so this
  // session survives while others are revoked).
  async changePassword({ currentPassword, newPassword }) {
    return unwrap(
      await api.post('/auth/change-password', {
        currentPassword,
        newPassword,
        refreshToken: tokenStore.refresh,
      })
    );
  },

  async logout() {
    try {
      await api.post('/auth/logout', { refreshToken: tokenStore.refresh });
    } catch {
      // best-effort revocation
    } finally {
      tokenStore.clear();
    }
  },
};
