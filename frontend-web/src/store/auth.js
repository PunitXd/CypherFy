// Global auth state (zustand). Holds the current user + a coarse status the
// router uses to gate screens.

import { create } from 'zustand';
import { authApi } from '../api/auth';
import { tokenStore } from '../api/client';
import { socketService } from '../socket/socket';
import { useRealtime } from './realtime';

export const useAuth = create((set) => ({
  user: null,
  status: 'idle', // idle | loading | authed | guest

  // Called once on app start: if we hold a token, resolve the current user.
  async bootstrap() {
    if (!tokenStore.access) {
      set({ status: 'guest' });
      return;
    }
    set({ status: 'loading' });
    try {
      const user = await authApi.me();
      set({ user, status: user ? 'authed' : 'guest' });
    } catch {
      set({ status: 'guest' });
    }
  },

  setUser(user) {
    set({ user, status: 'authed' });
  },

  // Merge a partial profile update into the current user.
  updateUser(patch) {
    set((s) => ({ user: s.user ? { ...s.user, ...patch } : patch }));
  },

  async logout() {
    await authApi.logout();
    socketService.disconnect();
    useRealtime.getState().reset();
    set({ user: null, status: 'guest' });
  },
}));
