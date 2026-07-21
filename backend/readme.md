# CypherFy — Backend

Node.js (ESM) + Express + Socket.io + MongoDB + Redis.

## Run

```bash
cp .env.example .env    # fill in secrets
npm install
npm run dev             # → "CypherFy running on port 8000"
```

Requires MongoDB (`MONGODB_URI`) and Redis (`REDIS_URL`) reachable.

## Layout

- `src/index.js` — entry: DB → Redis → Socket.io → listen.
- `src/app.js` — Express app, routes, health, error handler.
- `src/controllers` / `src/routes` — REST surface (`/api/v1/*`).
- `src/socket` — realtime layer; Redis adapter attached before any handler.
- `src/services` — redis, fcm, r2, email.
- `src/models` — Mongoose schemas (room, message, user, chatRequest).

## Security invariants

- Ciphertext only in MongoDB — never plaintext.
- No message content in logs or FCM notifications.
- Raw room keys never reach the server; only password-wrapped ciphertext.

## Notable endpoints

- `POST /api/v1/rooms` — create ephemeral room (guests allowed).
- `GET /api/v1/rooms/:code` — validate an ephemeral code.
- `GET /api/v1/rooms/permanent` — list DM rooms (auth).
- `POST /api/v1/requests` + `PATCH /:id/accept|reject` — chat-request flow.
- `GET /api/v1/upload/presigned-put|get` — direct-to-R2 encrypted blob transfer.
- `GET /api/v1/health` — mongo/redis status.
