# CypherFy — Web (React)

React + Vite web frontend for CypherFy. **Milestone 1: authentication** — the
lamp/pull-string login experience, fully wired to the backend. Chat, E2EE crypto,
and calls follow in later phases (see `../.claude/plans/`).

The Flutter app in `../frontend` remains the **mobile** client; this React app is
the **web** client. Both talk to the same backend.

## Getting started

```bash
npm install
cp .env.example .env      # defaults point at http://localhost:8000
npm run dev               # http://localhost:5173
```

The backend must be running (see `../backend` or `docker compose up backend redis`).

## Config (Vite env → `import.meta.env`)

| Var | Purpose |
| --- | --- |
| `VITE_API_BASE_URL` | Backend REST base, e.g. `http://localhost:8000/api/v1` |
| `VITE_SOCKET_URL` | Socket.io origin (used in later phases) |
| `VITE_GOOGLE_WEB_CLIENT_ID` | Google OAuth web client id |
| `VITE_FIREBASE_*` | Firebase web config for Google sign-in (blank ⇒ Google hidden) |

## What's implemented

- **Login** (`/`) — email/password → `POST /auth/login`; routes to `/verify` on the
  403 "unverified" response.
- **Register** (`/register`) — email, display name, username, password + confirm →
  `POST /auth/register` → OTP verification.
- **Verify** (`/verify`) — 6-digit email OTP → `POST /auth/verify-email` (+ resend).
- **Forgot / Reset** (`/forgot`, `/reset`) — OTP or emailed-link reset flow.
- **Google** — Firebase popup → `POST /auth/firebase` (when configured).
- Axios client with bearer injection + one-shot refresh-token rotation on 401
  (mirrors the Flutter `ApiClient`). Session tokens in `localStorage`.

## Structure

```
src/
├── api/          client.js (axios+refresh), auth.js (endpoints)
├── store/        auth.js (zustand)
├── components/   RoomScene, PasswordInput, GoogleButton, Notice, RequireAuth
├── layouts/      AuthLayout
├── screens/      Login, Register, Verify, Forgot, Reset, Home
├── firebase.js   lazy Google sign-in
└── config.js     env
```
