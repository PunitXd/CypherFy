// Express application setup — middleware, routes, health, error handler.
// The HTTP server and Socket.io are wired up in index.js.

import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import cookieParser from 'cookie-parser';
import mongoose from 'mongoose';

import authRoutes from './routes/auth.routes.js';
import userRoutes from './routes/user.routes.js';
import roomRoutes from './routes/room.routes.js';
import uploadRoutes from './routes/upload.routes.js';
import requestRoutes from './routes/requests.routes.js';
import callRoutes from './routes/call.routes.js';
import { apiLimiter } from './middlewares/rateLimit.middleware.js';
import { errorHandler, notFoundHandler } from './middlewares/error.middleware.js';
import { getRedis } from './services/redis.service.js';

export const app = express();

// Behind a reverse proxy (nginx / Render / Railway), Express must trust it so
// `req.ip` and X-Forwarded-For resolve to the real client — otherwise every
// request appears to come from the proxy and IP-based rate limiting collapses
// to a single bucket. Configurable via TRUST_PROXY (a hop count like "1", or a
// subnet); defaults to off for direct/local runs. Never trust *all* proxies in
// production — that lets clients spoof X-Forwarded-For to evade IP limits.
const trustProxy = process.env.TRUST_PROXY;
if (trustProxy !== undefined && trustProxy !== '') {
  app.set('trust proxy', /^\d+$/.test(trustProxy) ? Number(trustProxy) : trustProxy);
}

// --- Security + parsing middleware ---
app.use(helmet());
app.use(
  cors({
    origin: process.env.CLIENT_URL,
    credentials: true,
  })
);
app.use(express.json({ limit: '16kb' }));
app.use(express.urlencoded({ extended: true, limit: '16kb' }));
app.use(cookieParser());
app.use(express.static('public'));

// General rate-limit safety net across the API.
app.use('/api', apiLimiter);

// --- Routes ---
app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/users', userRoutes);
app.use('/api/v1/rooms', roomRoutes);
app.use('/api/v1/upload', uploadRoutes);
app.use('/api/v1/requests', requestRoutes);
app.use('/api/v1/calls', callRoutes);

// --- Health check ---
app.get('/api/v1/health', async (_req, res) => {
  // mongoose.connection.readyState: 1 === connected.
  const mongoOk = mongoose.connection.readyState === 1;
  let redisOk = false;
  try {
    redisOk = (await getRedis().ping()) === 'PONG';
  } catch {
    redisOk = false;
  }
  res.json({
    status: mongoOk && redisOk ? 'ok' : 'degraded',
    mongo: mongoOk ? 'connected' : 'down',
    redis: redisOk ? 'connected' : 'down',
    timestamp: new Date().toISOString(),
  });
});

// --- Unmatched routes → clean 404, then the global error handler (must be last) ---
// The error handler guarantees clients never see stack traces, file paths, or
// raw DB errors — see middlewares/error.middleware.js.
app.use(notFoundHandler);
app.use(errorHandler);
