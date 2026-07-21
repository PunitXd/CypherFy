// Firebase Cloud Messaging service.
//
// CRITICAL: notifications NEVER contain message content. We only ever tell the
// user that *something* happened ("New message from X"), never what was said.
//
// If Firebase credentials are not configured, every send becomes a no-op so the
// app still runs in local development without FCM set up.

// firebase-admin v13+ ships the modular API; the old namespaced `admin.messaging()`
// default export is gone under ESM, so import the specific entry points.
import { initializeApp, getApps, cert } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

let initialized = false;

/** Lazily initialise the Firebase Admin SDK from env credentials. */
const ensureInit = () => {
  if (initialized) return getApps().length > 0;

  initialized = true;
  const { FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY } =
    process.env;

  if (!FIREBASE_PROJECT_ID || !FIREBASE_CLIENT_EMAIL || !FIREBASE_PRIVATE_KEY) {
    console.warn('FCM disabled — Firebase credentials not configured.');
    return false;
  }

  // Reuse the default app if firebase.service.js (Auth) already created it —
  // a second initializeApp() throws `app/duplicate-app`.
  if (getApps().length > 0) return true;

  initializeApp({
    credential: cert({
      projectId: FIREBASE_PROJECT_ID,
      clientEmail: FIREBASE_CLIENT_EMAIL,
      // Env stores the key with literal \n; convert back to real newlines.
      privateKey: FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
    }),
  });
  console.log('FCM initialised');
  return true;
};

/** Send a push, swallowing errors (a failed notification must not crash flow). */
const send = async (token, title, body, data = {}) => {
  if (!token) return;
  if (!ensureInit()) return;
  try {
    await getMessaging().send({
      token,
      notification: { title, body },
      data, // data payload carries routing info only — never content
    });
  } catch (err) {
    console.error('FCM send failed:', err.message);
  }
};

// "New message from {senderName}" — content deliberately omitted.
export const sendMessageNotification = (fcmToken, senderName, roomId) =>
  send(fcmToken, 'CypherFy', `New message from ${senderName}`, {
    type: 'message',
    roomId: String(roomId),
  });

export const sendChatRequestNotification = (fcmToken, fromDisplayName) =>
  send(fcmToken, 'CypherFy', `${fromDisplayName} wants to chat`, {
    type: 'chat_request',
  });

export const sendKnockNotification = (fcmToken, alias, roomCode) =>
  send(fcmToken, 'CypherFy', `${alias} wants to join your room`, {
    type: 'knock',
    roomCode,
  });

export const sendRoomExpiringNotification = (fcmToken, roomCode) =>
  send(fcmToken, 'CypherFy', 'Your room expires in 60 seconds', {
    type: 'room_expiring',
    roomCode,
  });

// Call wake-up push. Unlike every other notification this is DATA-ONLY (no
// `notification` block) and HIGH priority, so the killed/backgrounded app's
// background isolate actually runs and can raise a native full-screen incoming-call
// ring (CallKit). Still content-free — only the caller's name/avatar for the UI.
// `ttl` stops the phone ringing for a call the caller already gave up on.
export const sendCallNotification = async (fcmToken, caller, callId, callType) => {
  if (!fcmToken) return;
  if (!ensureInit()) return;
  try {
    await getMessaging().send({
      token: fcmToken,
      data: {
        type: 'call',
        callId: String(callId || ''),
        callerName: String(caller?.name || 'Someone'),
        callerAvatar: String(caller?.avatar || ''),
        callType: String(callType || 'audio'),
      },
      android: { priority: 'high', ttl: 45000 },
    });
  } catch (err) {
    console.error('FCM call send failed:', err.message);
  }
};
