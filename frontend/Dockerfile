# syntax=docker/dockerfile:1

# ---- Stage 1: compile the Flutter web bundle ----
# Pinned to the project's Flutter version (built with 3.41.1; pubspec sdk >=3.3.0).
# cirruslabs publishes ready-to-use Flutter SDK images.
FROM ghcr.io/cirruslabs/flutter:3.41.1 AS build

# Compile-time config — Flutter bakes these in via --dart-define. Override per
# environment, e.g.:
#   --build-arg API_BASE_URL=https://api.cypherfy.in/api/v1 \
#   --build-arg SOCKET_URL=https://api.cypherfy.in \
#   --build-arg GOOGLE_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com
ARG API_BASE_URL=http://localhost:8000/api/v1
ARG SOCKET_URL=http://localhost:8000
ARG GOOGLE_WEB_CLIENT_ID=

WORKDIR /app

# Resolve dependencies first for better layer caching.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# App source, then build the release web bundle with the injected config.
COPY . .
RUN flutter build web --release \
      --dart-define=API_BASE_URL=$API_BASE_URL \
      --dart-define=SOCKET_URL=$SOCKET_URL \
      --dart-define=GOOGLE_WEB_CLIENT_ID=$GOOGLE_WEB_CLIENT_ID

# ---- Stage 2: serve the static bundle with nginx ----
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
