// Firebase Admin — verifies Firebase ID tokens minted by the client after any
// social sign-in (Google, Apple, …). We only use it as an identity front-door;
// our own JWTs still drive the session.
//
// IMPORTANT: this shares the SAME default Firebase Admin app that fcm.service.js
// initializes (one Firebase project = one service account, valid for both
// messaging and Auth token verification). Never call initializeApp() a second
// time — that throws `app/duplicate-app`. Credentials come from the same env
// trio FCM uses: FIREBASE_PROJECT_ID / FIREBASE_CLIENT_EMAIL / FIREBASE_PRIVATE_KEY.
// firebase-admin v13+ modular API (the namespaced `admin.auth()` default export
// is gone under ESM). `getApp` is aliased so it doesn't clash with the local one.
import {
  initializeApp,
  getApps,
  getApp as getAdminApp,
  cert,
} from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

export const isFirebaseConfigured = () =>
  Boolean(
    process.env.FIREBASE_PROJECT_ID &&
      process.env.FIREBASE_CLIENT_EMAIL &&
      process.env.FIREBASE_PRIVATE_KEY
  );

// Initialise (once) and return the Admin app, reusing the default app if FCM
// (or a prior call) already created it. Throws if unconfigured — callers should
// guard with isFirebaseConfigured() and surface a clean error.
const getApp = () => {
  if (getApps().length > 0) return getAdminApp();

  const { FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY } =
    process.env;

  return initializeApp({
    credential: cert({
      projectId: FIREBASE_PROJECT_ID,
      clientEmail: FIREBASE_CLIENT_EMAIL,
      // Env stores the key with literal \n; convert back to real newlines.
      privateKey: FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
    }),
  });
};

// Verify a Firebase ID token → decoded claims (uid, email, name, picture,
// firebase.sign_in_provider, …). Throws on an invalid/expired token.
export const verifyFirebaseToken = (idToken) => getAuth(getApp()).verifyIdToken(idToken);
