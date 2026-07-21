# syntax=docker/dockerfile:1

# ---- CypherFy backend — Express + Socket.io + MongoDB + Redis ----
# Plain Node ESM app (no build step). bcryptjs is pure-JS, so no native
# toolchain is needed and alpine stays slim.
FROM node:22-alpine

ENV NODE_ENV=production
WORKDIR /app

# Install production deps first so this layer is cached until the lockfile
# changes. --omit=dev drops nodemon (only used by `npm run dev`).
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Application source.
COPY . .

# Multer buffers avatar uploads to ./public/temp before streaming them to R2.
# Ensure the dir exists and everything is owned by the non-root runtime user.
RUN mkdir -p public/temp && chown -R node:node /app

USER node
EXPOSE 8000

# Liveness: the health route returns HTTP 200 with a mongo/redis status body.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://localhost:8000/api/v1/health || exit 1

CMD ["node", "src/index.js"]
