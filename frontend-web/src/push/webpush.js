// Web push via Firebase Cloud Messaging — content-free notifications (matches the
// backend invariant). Fully config-gated: a no-op unless Firebase + a VAPID key
// are provided, so the app runs fine without it.
//
// Needs: VITE_FIREBASE_* (see config.js) + VITE_FIREBASE_VAPID_KEY, and the
// service worker at public/firebase-messaging-sw.js (fill in the same config).

import { isFirebaseConfigured } from '../firebase';
import { socketService } from '../socket/socket';

const VAPID_KEY = import.meta.env.VITE_FIREBASE_VAPID_KEY || '';

export function pushSupported() {
  return (
    typeof window !== 'undefined' &&
    'Notification' in window &&
    'serviceWorker' in navigator
  );
}

export function pushConfigured() {
  return isFirebaseConfigured() && Boolean(VAPID_KEY);
}

// Request permission, obtain an FCM token, and register it with the backend.
export async function enableWebPush() {
  if (!pushSupported()) return { ok: false, reason: 'This browser does not support notifications' };
  if (!pushConfigured()) return { ok: false, reason: 'Push is not configured on this build' };

  const perm = await Notification.requestPermission();
  if (perm !== 'granted') return { ok: false, reason: 'Notification permission was denied' };

  const { initializeApp, getApps } = await import('firebase/app');
  const { getMessaging, getToken } = await import('firebase/messaging');
  const { FIREBASE } = await import('../config');

  const app = getApps().length ? getApps()[0] : initializeApp(FIREBASE);
  const reg = await navigator.serviceWorker.register('/firebase-messaging-sw.js');
  const messaging = getMessaging(app);
  const token = await getToken(messaging, { vapidKey: VAPID_KEY, serviceWorkerRegistration: reg });
  if (!token) return { ok: false, reason: 'Could not obtain a push token' };

  // Register with the backend over the socket (fcm token save is a socket event).
  if (socketService.connected) {
    socketService.emit('save_fcm_token', { token });
    return { ok: true, token };
  }
  return {
    ok: true,
    token,
    note: 'Token obtained — open a chat to finish registering (socket not connected).',
  };
}
