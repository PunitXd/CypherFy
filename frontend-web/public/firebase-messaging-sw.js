/* Firebase Cloud Messaging service worker for background push.
 *
 * Service workers can't read Vite env vars, so fill in the SAME web config you
 * put in VITE_FIREBASE_* here to enable background notifications. Left as
 * placeholders — background push is inert until these are set.
 *
 * Notifications are intentionally content-free (matches the backend: no message
 * text is ever sent in a push).
 */
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

const firebaseConfig = {
  apiKey: '',
  authDomain: '',
  projectId: '',
  messagingSenderId: '',
  appId: '',
};

if (firebaseConfig.apiKey) {
  firebase.initializeApp(firebaseConfig);
  const messaging = firebase.messaging();

  messaging.onBackgroundMessage((payload) => {
    const title = payload?.notification?.title || 'CypherFy';
    const body = payload?.notification?.body || 'You have a new notification';
    self.registration.showNotification(title, { body, icon: '/favicon.svg' });
  });
}
