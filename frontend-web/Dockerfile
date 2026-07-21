# syntax=docker/dockerfile:1

# ---- Stage 1: build the React (Vite) bundle ----
FROM node:22-alpine AS build

# Compile-time config — Vite bakes VITE_* into the bundle, so these are build
# args, not runtime env. Override per environment, e.g.:
#   --build-arg VITE_API_BASE_URL=https://api.cypherfy.in/api/v1 \
#   --build-arg VITE_SOCKET_URL=https://api.cypherfy.in
# In the dockerized stack the browser runs on the host and reaches the backend
# via the published :8000 port, and the backend's CLIENT_URL (:8080) matches this
# app's origin, so CORS works directly — no dev proxy needed.
ARG VITE_API_BASE_URL=http://localhost:8000/api/v1
ARG VITE_SOCKET_URL=http://localhost:8000
ARG VITE_GOOGLE_WEB_CLIENT_ID=
ARG VITE_FIREBASE_API_KEY=
ARG VITE_FIREBASE_AUTH_DOMAIN=
ARG VITE_FIREBASE_PROJECT_ID=
ARG VITE_FIREBASE_APP_ID=
ARG VITE_FIREBASE_VAPID_KEY=

# Actual env vars take precedence over any .env file, so these win at build time.
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL \
    VITE_SOCKET_URL=$VITE_SOCKET_URL \
    VITE_GOOGLE_WEB_CLIENT_ID=$VITE_GOOGLE_WEB_CLIENT_ID \
    VITE_FIREBASE_API_KEY=$VITE_FIREBASE_API_KEY \
    VITE_FIREBASE_AUTH_DOMAIN=$VITE_FIREBASE_AUTH_DOMAIN \
    VITE_FIREBASE_PROJECT_ID=$VITE_FIREBASE_PROJECT_ID \
    VITE_FIREBASE_APP_ID=$VITE_FIREBASE_APP_ID \
    VITE_FIREBASE_VAPID_KEY=$VITE_FIREBASE_VAPID_KEY

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# ---- Stage 2: serve the static bundle with nginx ----
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
