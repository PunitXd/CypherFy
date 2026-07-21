# Security notes — secrets & keys

## Secrets model
- **Backend secrets** (JWT signing keys, `MONGODB_URI`, Cloudflare R2 keys, SMTP
  password, Firebase Admin private key, TURN credentials) live only in
  `backend/.env`, are read via `process.env.*`, and are **gitignored**. Never
  commit real values — `backend/.env.example` holds placeholders only.
- **Frontend config** is injected at build time, never hardcoded:
  - React (`frontend-web`): `import.meta.env.VITE_*` (see `src/config.js`).
  - Flutter (`frontend`): `String.fromEnvironment(...)` via `--dart-define`.
- Verified: a production React build contains **no** backend secret value
  (JWT/R2/SMTP/Mongo/Firebase-admin) — only client-safe config ships.

## Firebase client API keys — important
The Firebase API keys in `firebase_options.dart`, `google-services.json`, and
`GoogleService-Info.plist` are **client identifiers, not secrets**. They are
compiled into every shipped app (APK / IPA / web bundle) and can always be
extracted from the client — this is by design
(https://firebase.google.com/docs/projects/api-keys). No amount of code hiding
changes that.

What we do about them:
1. **Kept out of the repo** — all three files are gitignored. A public mirror
   exposes no project config. Regenerate locally with `flutterfire configure`.
2. **Real protection is enforced in the Google Cloud / Firebase console** (a
   harvested key is then useless outside your app):

### Console hardening checklist (do this in the dashboard)
- [ ] **Restrict each API key** — Google Cloud Console → APIs & Services →
      Credentials → (each Firebase key):
      - Application restrictions: Android app (package name + SHA-256 signing
        fingerprint), iOS app (bundle ID), and/or HTTP referrers (your web
        domain, e.g. `cypherfy.in`).
      - API restrictions: allow only the Firebase/Google APIs the app uses
        (Identity Toolkit, Token Service, FCM, etc.).
- [ ] **Enable Firebase App Check** — attests that requests come from your
      genuine app (Play Integrity on Android, DeviceCheck/App Attest on iOS,
      reCAPTCHA on web), then enforce it on the Firebase services you use.
- [ ] **Lock down Firebase Security Rules** — the API key grants no data access;
      your rules do. Default-deny, then allow only what's needed.

## Reporting
Found a vulnerability? Email <punitxd.23@gmail.com> rather than opening a public
issue.
