// Socket.io initialisation.
//
// Order matters (per spec): the Redis adapter MUST be attached BEFORE any
// connection handlers run, so events fan out across every server instance.
//
// Auth is optional at the socket level: guests connect anonymously for
// ephemeral rooms; account users pass a JWT so we can route DMs and presence to
// them. A verified user id is stashed on socket.data.userId.

import { Server } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import jwt from 'jsonwebtoken';
import { User } from '../models/user.model.js';
import { getRedis } from '../services/redis.service.js';
import { registerRoomHandlers } from './handlers/room.handler.js';
import { registerMessageHandlers } from './handlers/message.handler.js';
import { registerKnockHandlers } from './handlers/knock.handler.js';
import { registerWebrtcHandlers } from './handlers/webrtc.handler.js';
import { registerNotifHandlers } from './handlers/notif.handler.js';
import { setSocketUser, removeSocketUser, setDisconnectTime } from '../services/redis.service.js';
import { ERROR_CODES, SOCKET_EVENTS } from '../constants.js';

let io = null;

/** Access the initialised io instance from anywhere (e.g. controllers). */
export const getIO = () => {
  if (!io) throw new Error('Socket.io not initialised — call initSocket() first');
  return io;
};

/**
 * Initialise Socket.io on the given HTTP server.
 * @param {import('http').Server} httpServer
 */
export const initSocket = (httpServer) => {
  io = new Server(httpServer, {
    cors: {
      origin: process.env.CLIENT_URL,
      credentials: true,
    },
    // Encrypted file messages can carry small payloads; give some headroom.
    maxHttpBufferSize: 2 * 1024 * 1024,
  });

  // --- Redis adapter FIRST (before any socket.on) ---
  const pubClient = getRedis();
  const subClient = pubClient.duplicate();
  io.adapter(createAdapter(pubClient, subClient));

  // --- Optional JWT auth on the handshake ---
  io.use(async (socket, next) => {
    const token =
      socket.handshake.auth?.token ||
      socket.handshake.headers?.authorization?.replace('Bearer ', '');

    if (!token) {
      // Guest connection — allowed, but no account features.
      socket.data.userId = null;
      return next();
    }
    try {
      const decoded = jwt.verify(token, process.env.ACCESS_TOKEN_SECRET);
      // Reject tokens minted before the last password change (mirrors verifyJWT)
      // so a reset/change signs out this device on the socket layer too.
      const user = await User.findById(decoded._id).select('passwordChangedAt');
      socket.data.userId =
        user && !user.changedPasswordAfter(decoded.iat) ? decoded._id : null;
    } catch {
      // Bad token → treat as guest rather than refusing the connection.
      socket.data.userId = null;
    }
    return next();
  });

  // --- Connection lifecycle ---
  io.on('connection', async (socket) => {
    // Account users get a private room "user:<id>" for DMs, requests, presence.
    if (socket.data.userId) {
      socket.join(`user:${socket.data.userId}`);
      await setSocketUser(socket.id, socket.data.userId).catch(() => {});
    }

    // A tiny helper handlers use to emit a structured error to just this socket.
    socket.emitError = (code, message) =>
      socket.emit(SOCKET_EVENTS.ERROR, { code, message });

    // Register every feature's handlers. Each wraps its logic in try/catch so a
    // single bad event can never crash the server.
    registerRoomHandlers(io, socket);
    registerMessageHandlers(io, socket);
    registerKnockHandlers(io, socket);
    registerWebrtcHandlers(io, socket);
    registerNotifHandlers(io, socket);

    socket.on('disconnect', async () => {
      // Record disconnect time so FCM logic knows when it's safe to notify.
      await setDisconnectTime(socket.id).catch(() => {});
      await removeSocketUser(socket.id).catch(() => {});
      // Room-specific cleanup (presence removal, user_left) is handled inside
      // the room handler's disconnect hook.
    });
  });

  console.log('Socket.io initialised with Redis adapter');
  return io;
};

// Re-export for convenience in handlers that want the canonical error codes.
export { ERROR_CODES };
