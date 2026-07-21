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

## Security invariants

1. No plaintext in MongoDB.
2. No plaintext in logs.
3. No raw encryption key on the server (only password-wrapped ciphertext).
4. FCM notifications never include message content.
