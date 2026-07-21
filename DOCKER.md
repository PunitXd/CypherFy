# Running CypherFy with Docker

Three images make up the stack:

| Service    | Image                          | Port        | Notes                                    |
| ---------- | ------------------------------ | ----------- | ---------------------------------------- |
| `backend`  | `backend/Dockerfile`           | `8000`      | Express + Socket.io (Node 22, alpine)    |
| `frontend` | `frontend-web/Dockerfile`      | `8080`→`80` | React (Vite) web app served by nginx     |
| `redis`    | `redis:7-alpine`               | internal    | Socket.io adapter + presence / TTL store |

MongoDB is **not** containerised by default — the backend points at MongoDB
Atlas via `MONGODB_URI`. A commented `mongo` service in `docker-compose.yml`
lets you run it locally instead.

## Quick start (whole stack)

```bash
cp backend/.env.example backend/.env     # fill in Mongo/JWT/R2/FCM/SMTP secrets
docker compose up --build
```

- Frontend → http://localhost:8080
- Backend  → http://localhost:8000/api/v1/health

Compose overrides two values from `backend/.env` so the containers talk to each
other correctly:

- `REDIS_URL=redis://redis:6379` (service name, not `localhost`)
- `CLIENT_URL=http://localhost:8080` (CORS allow-origin = where the UI is served)

## Building the images individually

**Backend**

```bash
docker build -t cypherfy-backend ./backend
docker run --rm -p 8000:8000 --env-file backend/.env \
  -e REDIS_URL=redis://host.docker.internal:6379 \
  cypherfy-backend
```

**Frontend** (React, in `frontend-web/`) — the API/socket URLs, Google client id,
and Firebase config are compile-time and must be passed as build args (Vite bakes
them into the JS bundle):

```bash
docker build -t cypherfy-frontend ./frontend-web \
  --build-arg VITE_API_BASE_URL=https://api.cypherfy.in/api/v1 \
  --build-arg VITE_SOCKET_URL=https://api.cypherfy.in \
  --build-arg VITE_GOOGLE_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com
docker run --rm -p 8080:80 cypherfy-frontend
```

> The legacy Flutter web build in `./frontend` is kept for the mobile codebase but
> is no longer served by compose. Firebase args (`VITE_FIREBASE_*`) are optional —
> only needed for Google sign-in and web push.

## Deploying to production — checklist

- **Rebuild the frontend per environment.** `VITE_API_BASE_URL` / `VITE_SOCKET_URL`
  / `VITE_GOOGLE_WEB_CLIENT_ID` are frozen at build time; the same image can't be
  repointed at runtime. Build with your real API origin.
- **Set `CLIENT_URL`** on the backend to the exact frontend origin — it is the
  sole CORS allow-origin.
- **TLS / WebSockets.** Terminate HTTPS at a reverse proxy in front of the
  backend and forward the `Upgrade`/`Connection` headers so Socket.io's
  websocket transport works.
- **Secrets** (`backend/.env`) are injected at runtime and never baked into the
  image (`.dockerignore` excludes `.env`). Use your platform's secret manager.
- The frontend image is stateless static content — put it behind a CDN or serve
  directly; nginx already handles SPA fallback + asset caching.
