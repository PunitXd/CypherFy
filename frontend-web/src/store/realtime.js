import { create } from 'zustand';

// Live-presence + activity state fed by the shell's persistent socket.
export const useRealtime = create((set) => ({
  onlineUsers: {}, // userId -> { isOnline, lastSeenAt }
  dmTick: 0, // bumped when the DM list should refetch
  requestsCount: 0, // pending incoming chat requests (badge)

  setOnline(userId, isOnline, lastSeenAt) {
    set((s) => ({ onlineUsers: { ...s.onlineUsers, [String(userId)]: { isOnline, lastSeenAt } } }));
  },
  bumpDm() {
    set((s) => ({ dmTick: s.dmTick + 1 }));
  },
  incRequests() {
    set((s) => ({ requestsCount: s.requestsCount + 1 }));
  },
  setRequests(n) {
    set({ requestsCount: n });
  },
  reset() {
    set({ onlineUsers: {}, dmTick: 0, requestsCount: 0 });
  },
}));
