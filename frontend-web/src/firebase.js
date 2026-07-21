// Firebase Google sign-in — lazily loaded so the (large) SDK is only pulled in
// when a user actually clicks "Continue with Google", and the app runs fine
// when Firebase isn't configured.

import { FIREBASE } from './config';

let _app = null;

export function isFirebaseConfigured() {
  return Boolean(FIREBASE.apiKey && FIREBASE.authDomain && FIREBASE.projectId);
}

async function getAuthInstance() {
  const { initializeApp, getApps } = await import('firebase/app');
  const { getAuth } = await import('firebase/auth');
  if (!_app) _app = getApps().length ? getApps()[0] : initializeApp(FIREBASE);
  return getAuth(_app);
}

// Opens the Google popup and returns a Firebase ID token to hand to our backend.
export async function signInWithGoogle() {
  const { GoogleAuthProvider, signInWithPopup } = await import('firebase/auth');
  const auth = await getAuthInstance();
  const provider = new GoogleAuthProvider();
  const cred = await signInWithPopup(auth, provider);
  return cred.user.getIdToken();
}
