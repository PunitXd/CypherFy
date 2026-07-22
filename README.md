# CypherFy

A production-ready, end-to-end encrypted chat application with two experiences:

- **Ephemeral anonymous rooms** — zero-friction, 6-char code, key lives only in the URL hash, auto-deletes on a TTL.
- **Permanent encrypted DMs** — Instagram-style, account-only, fully E2E encrypted with password-wrapped room keys.

## Structure

```
cypherfy/
├── frontend/   ← Flutter (web + Android + iOS)
├── backend/    ← Node.js (Express + Socket.io + MongoDB + Redis)
├── .gitignore
└── README.md
```

## Encryption model

- **AES-256-GCM** for every message, file, file-metadata blob, and stored room key.
- Ephemeral room keys exist **only** in the URL hash fragment — the server never sees them.
- Permanent room keys are wrapped with a key derived from the user's password
  (`PBKDF2(password, userId, 100000, SHA-256)`) and stored as ciphertext only.
- The server stores **ciphertext only** — never plaintext, never a raw key.

## Backend — getting started

```bash
cd backend
cp .env.example .env      # fill in your secrets
npm install
npm run dev               # → "CypherFy running on port 8000"
```

Requires MongoDB and Redis reachable via `MONGODB_URI` / `REDIS_URL`.

## Frontend — getting started

```bash
cd frontend
flutter pub get
flutter run -d chrome
```

The above talks to a local backend — `API_BASE_URL`, `SOCKET_URL` and
`GOOGLE_WEB_CLIENT_ID` all fall back to `localhost:8000` defaults, which is what
you want in dev.

## Release build (Android)

Once per clone, copy the template and fill in the real production values:

```bash
cd frontend
cp dart_defines.example.json dart_defines.json
```

Then build:

```bash
flutter build apk --release --dart-define-from-file=dart_defines.json
```

**The flag is not optional.** `API_BASE_URL`, `SOCKET_URL` and
`GOOGLE_WEB_CLIENT_ID` are read via `String.fromEnvironment`, which is `const` —
the localhost defaults get inlined into the AOT snapshot at build time. A plain
`flutter build apk --release` therefore emits a perfectly valid, signed APK that
points every request at the phone itself, with no error or warning at build
time. It surfaces only after install, as "the backend is down" against a
healthy server. Omitting the flag is silent; omitting the *file* is a loud
build error, which is why the values are not baked into the source.

Verify before uploading — this must print the production host, and no
`localhost` or `your-domain.example`:

```bash
unzip -p build/app/outputs/flutter-apk/app-release.apk lib/arm64-v8a/libapp.so \
  | grep -aoE 'https?://[a-zA-Z0-9._:-]+'
```

`dart_defines.json` is gitignored, alongside `android/key.properties` and
`backend/.env`.

## Security invariants

1. No plaintext in MongoDB.
2. No plaintext in logs.
3. No raw encryption key on the server (only password-wrapped ciphertext).
4. FCM notifications never include message content.
