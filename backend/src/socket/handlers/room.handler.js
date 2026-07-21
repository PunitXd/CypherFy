// Room handler — the heart of the realtime layer.
//
// Covers: create_room, join_room, join_permanent, leave_room, end_room, typing,
// and per-socket disconnect cleanup. Also schedules the 60-second expiry warning
// and the auto-delete for ephemeral rooms, resetting the timers whenever a room
// sees activity (so an active room never dies).

import { Room } from '../../models/room.model.js';
import { Message } from '../../models/message.model.js';
import { User } from '../../models/user.model.js';
import { sendRoomExpiringNotification } from '../../services/fcm.service.js';
import {
  addUserToRoom,
  removeUserFromRoom,
  getRoomUsers,
  setAlias,
  getAlias,
  getAllAliases,
  removeAlias,
  setColor,
  setTyping,
  clearTyping,
  cleanupRoom,
  isAdmitted,
  getPendingKnocks,
} from '../../services/redis.service.js';
import { deleteBlobsByRoom } from '../../services/r2.service.js';
import { getIceConfig } from '../../services/ice.service.js';
import { generateColor } from '../../utils/aliasGenerator.js';
import { validatePayload } from '../../middlewares/validate.middleware.js';
import { socketSchemas } from '../../validators/socket.schemas.js';
import {
  SOCKET_EVENTS,
  ERROR_CODES,
  ROOM,
} from '../../constants.js';

// Per-room expiry timers, keyed by room code. Module-level so activity in any
// handler can reset them via touchRoom().
const roomTimers = new Map();

// WebRTC ICE config sent to clients on join (STUN + optional TURN from env).
// Shared with the call handler via ice.service.js.
const iceConfig = getIceConfig();

/**
 * (Re)schedule the expiry warning + auto-delete for an ephemeral room and push
 * lastActivityAt forward in Mongo. Call on any activity to keep the room alive.
 * Exported so the message handler can reset the clock on every message.
 */
export const touchRoom = async (io, code, ttlSeconds) => {
  // Bump the DB TTL anchor to now + ttl.
  const expiresAt = new Date(Date.now() + ttlSeconds * 1000);
  await Room.updateOne(
    { code, type: 'ephemeral' },
    { $set: { lastActivityAt: expiresAt } }
  ).catch(() => {});

  // Clear any existing timers for this room.
  const existing = roomTimers.get(code);
  if (existing) {
    clearTimeout(existing.warn);
    clearTimeout(existing.expire);
  }

  const warnMs = Math.max(
    (ttlSeconds - ROOM.EXPIRY_WARNING_SECONDS) * 1000,
    0
  );
  const expireMs = ttlSeconds * 1000;

  const warn = setTimeout(async () => {
    io.to(code).emit(SOCKET_EVENTS.ROOM_EXPIRING, {
      secondsLeft: ROOM.EXPIRY_WARNING_SECONDS,
    });
    // Also push the host if they've stepped away — their room is about to
    // auto-delete from inactivity, so give them a chance to come back.
    try {
      const room = await Room.findOne({ code, type: 'ephemeral' }).select(
        'createdBy createdByUserId'
      );
      if (room?.createdByUserId) {
        const aliases = await getAllAliases(code); // socketId → alias
        const hostPresent = Object.values(aliases).includes(room.createdBy);
        if (!hostPresent) {
          const host = await User.findById(room.createdByUserId).select(
            'fcmTokens'
          );
          for (const token of host?.fcmTokens || []) {
            sendRoomExpiringNotification(token, code);
          }
        }
      }
    } catch (e) {
      console.error('room-expiring push failed:', e.message);
    }
  }, warnMs);

  const expire = setTimeout(() => {
    destroyRoom(io, code).catch((e) =>
      console.error('Auto-expire failed:', e.message)
    );
  }, expireMs);

  roomTimers.set(code, { warn, expire });
};

/**
 * Fully tear down an ephemeral room: delete R2 blobs, Message docs, the Room
 * doc, Redis state, timers, and notify everyone still connected.
 * @param {boolean} hostEnded true → emit room_ended, false → room_expired
 */
export const destroyRoom = async (io, code, hostEnded = false) => {
  const room = await Room.findOne({ code, type: 'ephemeral' });

  if (room) {
    // Collect every file blob for this room and batch-delete from R2.
    const fileMsgs = await Message.find({
      roomId: room._id,
      type: 'file',
    }).select('blobName');
    const blobNames = fileMsgs.map((m) => m.blobName).filter(Boolean);
    await deleteBlobsByRoom(blobNames).catch(() => {});

    await Message.deleteMany({ roomId: room._id });
    await Room.deleteOne({ _id: room._id });
  }

  await cleanupRoom(code).catch(() => {});

  const timers = roomTimers.get(code);
  if (timers) {
    clearTimeout(timers.warn);
    clearTimeout(timers.expire);
    roomTimers.delete(code);
  }

  io.to(code).emit(
    hostEnded ? SOCKET_EVENTS.ROOM_ENDED : SOCKET_EVENTS.ROOM_EXPIRED,
    {}
  );
  // Force everyone out of the socket.io room.
  io.socketsLeave(code);
};

export const registerRoomHandlers = (io, socket) => {
  // Track rooms this socket belongs to, for disconnect cleanup.
  socket.data.rooms = socket.data.rooms || new Set();

  // ---- create_room (ephemeral) ----------------------------------------
  socket.on(SOCKET_EVENTS.CREATE_ROOM, async (rawPayload, cb) => {
    const v = validatePayload(socketSchemas.createRoom, rawPayload);
    if (!v.ok) return socket.emitError('BAD_PAYLOAD', v.error[0]?.message || 'Invalid room');
    const payload = v.data;
    try {
      const {
        name,
        maxUsers = ROOM.DEFAULT_MAX_USERS,
        isLocked = false,
        passHint = null,
        ttlSeconds = ROOM.DEFAULT_TTL,
        alias,
      } = payload;

      if (!alias) return socket.emitError(ERROR_CODES.UNAUTHORIZED, 'alias required');

      // Reuse REST create logic inline to keep a single socket round-trip.
      const { generateRoomCode } = await import('../../utils/codeGenerator.js');
      let code;
      for (let i = 0; i < 5; i++) {
        code = generateRoomCode();
        // eslint-disable-next-line no-await-in-loop
        if (!(await Room.exists({ code }))) break;
        code = null;
      }
      if (!code) return socket.emitError('SERVER', 'Could not allocate a code');

      const room = await Room.create({
        type: 'ephemeral',
        name: name || 'Cypher Room',
        createdBy: alias, // the host is identified by alias for ephemeral rooms
        createdByUserId: socket.data.userId || null, // account id when logged in
        code,
        maxUsers,
        isLocked,
        passHashHint: passHint,
        inactivityTTL: ttlSeconds,
        lastActivityAt: new Date(Date.now() + ttlSeconds * 1000),
        currentUsers: [socket.id],
      });

      // Join and set up presence/alias/colour.
      await joinSocketToRoom(io, socket, room, alias);
      await touchRoom(io, code, ttlSeconds);

      const response = {
        code: room.code,
        roomId: room._id,
        expiresAt: room.lastActivityAt,
      };
      socket.emit(SOCKET_EVENTS.ROOM_CREATED, response);
      if (typeof cb === 'function') cb({ ok: true, ...response });
    } catch (err) {
      console.error('create_room error:', err.message);
      socket.emitError('SERVER', 'Failed to create room');
    }
  });

  // ---- join_room (ephemeral) ------------------------------------------
  socket.on(SOCKET_EVENTS.JOIN_ROOM, async (rawPayload, cb) => {
    const v = validatePayload(socketSchemas.joinRoom, rawPayload);
    if (!v.ok) {
      return socket.emitError(ERROR_CODES.INVALID_CODE, v.error[0]?.message || 'code and alias required');
    }
    const payload = v.data;
    try {
      const { code: rawCode, alias } = payload;
      const code = rawCode.toUpperCase();

      const room = await Room.findOne({ code, type: 'ephemeral' });
      if (!room) {
        return socket.emitError(ERROR_CODES.ROOM_NOT_FOUND, 'Room not found or expired');
      }

      // Capacity check against live presence.
      const users = await getRoomUsers(code);
      if (users.length >= room.maxUsers && !users.includes(socket.id)) {
        return socket.emitError(ERROR_CODES.ROOM_FULL, 'Room is full');
      }

      // Locked rooms require the host OR a socket the host has admitted.
      // Non-admitted, non-host joiners are rejected and must knock first.
      if (room.isLocked && room.createdBy !== alias) {
        const admitted = await isAdmitted(code, socket.id);
        if (!admitted) {
          return socket.emitError(
            ERROR_CODES.WRONG_PASSPHRASE,
            'Room is locked — knock to request entry'
          );
        }
      }

      await joinSocketToRoom(io, socket, room, alias);
      await touchRoom(io, code, room.inactivityTTL);

      // Send recent history (ciphertext only) back to the joiner.
      const messages = await Message.find({ roomId: room._id })
        .sort({ createdAt: 1 })
        .limit(200);

      const aliases = await getAllAliases(code);
      const payloadOut = {
        room: {
          roomId: room._id,
          code: room.code,
          name: room.name,
          maxUsers: room.maxUsers,
          isLocked: room.isLocked,
          createdBy: room.createdBy,
          expiresAt: room.lastActivityAt,
          isHost: room.createdBy === alias,
        },
        messages,
        users: Object.entries(aliases).map(([sid, a]) => ({ socketId: sid, alias: a })),
        iceConfig,
      };
      socket.emit(SOCKET_EVENTS.ROOM_JOINED, payloadOut);
      if (typeof cb === 'function') cb({ ok: true, ...payloadOut });

      // If the HOST just (re)joined a locked room, deliver any knocks that
      // came in before they were present — otherwise those joiners wait forever.
      if (room.isLocked && room.createdBy === alias) {
        const pending = await getPendingKnocks(code);
        for (const k of pending) {
          socket.emit(SOCKET_EVENTS.KNOCK_REQUEST, {
            alias: k.alias,
            socketId: k.socketId,
          });
        }
      }
    } catch (err) {
      console.error('join_room error:', err.message);
      socket.emitError('SERVER', 'Failed to join room');
    }
  });

  // ---- join_permanent (account users) ---------------------------------
  socket.on(SOCKET_EVENTS.JOIN_PERMANENT, async (rawPayload, cb) => {
    const v = validatePayload(socketSchemas.joinPermanent, rawPayload);
    if (!v.ok) return socket.emitError(ERROR_CODES.ROOM_NOT_FOUND, v.error[0]?.message || 'Invalid conversation');
    const payload = v.data;
    try {
      const { roomId } = payload;
      if (!socket.data.userId) {
        return socket.emitError(ERROR_CODES.UNAUTHORIZED, 'Login required');
      }
      const room = await Room.findById(roomId);
      if (!room || room.type !== 'permanent') {
        return socket.emitError(ERROR_CODES.ROOM_NOT_FOUND, 'Conversation not found');
      }
      if (!room.participants.some((p) => String(p) === String(socket.data.userId))) {
        return socket.emitError(ERROR_CODES.UNAUTHORIZED, 'Not a participant');
      }

      // Permanent rooms are namespaced by their id.
      const roomChannel = `perm:${room._id}`;
      socket.join(roomChannel);
      socket.data.rooms.add(roomChannel);

      // Only messages not deleted for this user.
      const messages = await Message.find({
        roomId: room._id,
        deletedFor: { $ne: socket.data.userId },
      })
        .sort({ createdAt: 1 })
        .limit(500);

      const payloadOut = {
        room: { roomId: room._id, name: room.name, type: 'permanent' },
        messages,
        iceConfig,
      };
      socket.emit(SOCKET_EVENTS.ROOM_JOINED, payloadOut);
      if (typeof cb === 'function') cb({ ok: true, ...payloadOut });
    } catch (err) {
      console.error('join_permanent error:', err.message);
      socket.emitError('SERVER', 'Failed to open conversation');
    }
  });

  // ---- end_room (host only, ephemeral) --------------------------------
  socket.on(SOCKET_EVENTS.END_ROOM, async (rawPayload) => {
    const v = validatePayload(socketSchemas.endRoom, rawPayload);
    if (!v.ok) return;
    try {
      const { roomCode } = v.data;
      const code = roomCode.toUpperCase();

      const room = await Room.findOne({ code, type: 'ephemeral' });
      if (!room) return socket.emitError(ERROR_CODES.ROOM_NOT_FOUND, 'Room not found');

      // Only the host (matched by alias) may end the room.
      const myAlias = await getAlias(code, socket.id);
      if (room.createdBy !== myAlias) {
        return socket.emitError(ERROR_CODES.NOT_HOST, 'Only the host can end the room');
      }

      await destroyRoom(io, code, true);
    } catch (err) {
      console.error('end_room error:', err.message);
      socket.emitError('SERVER', 'Failed to end room');
    }
  });

  // ---- leave_room -----------------------------------------------------
  socket.on(SOCKET_EVENTS.LEAVE_ROOM, async (rawPayload) => {
    const v = validatePayload(socketSchemas.leaveRoom, rawPayload);
    if (!v.ok) return;
    try {
      const { roomCode } = v.data;
      await leaveEphemeralRoom(io, socket, roomCode.toUpperCase());
    } catch (err) {
      console.error('leave_room error:', err.message);
    }
  });

  // ---- typing indicators ----------------------------------------------
  socket.on(SOCKET_EVENTS.TYPING_START, async (rawPayload) => {
    const v = validatePayload(socketSchemas.typing, rawPayload);
    if (!v.ok) return;
    try {
      const { roomId, code } = v.data;
      const channel = code ? code.toUpperCase() : `perm:${roomId}`;
      const alias =
        (code && (await getAlias(code.toUpperCase(), socket.id))) || socket.data.displayName || 'Someone';
      await setTyping(roomId || channel, alias);
      socket.to(channel).emit(SOCKET_EVENTS.TYPING_UPDATE, { alias, isTyping: true });
    } catch (err) {
      console.error('typing_start error:', err.message);
    }
  });

  socket.on(SOCKET_EVENTS.TYPING_STOP, async (rawPayload) => {
    const v = validatePayload(socketSchemas.typing, rawPayload);
    if (!v.ok) return;
    try {
      const { roomId, code } = v.data;
      const channel = code ? code.toUpperCase() : `perm:${roomId}`;
      const alias =
        (code && (await getAlias(code.toUpperCase(), socket.id))) || socket.data.displayName || 'Someone';
      await clearTyping(roomId || channel, alias);
      socket.to(channel).emit(SOCKET_EVENTS.TYPING_UPDATE, { alias, isTyping: false });
    } catch (err) {
      console.error('typing_stop error:', err.message);
    }
  });

  // ---- disconnect cleanup ---------------------------------------------
  socket.on('disconnect', async () => {
    try {
      // Leave every ephemeral room this socket was in, updating presence.
      for (const channel of socket.data.rooms) {
        if (channel.startsWith('perm:')) continue; // permanent rooms need no cleanup
        await leaveEphemeralRoom(io, socket, channel, /*silent*/ false);
      }
    } catch (err) {
      console.error('room disconnect cleanup error:', err.message);
    }
  });
};

// ---- Shared helpers -----------------------------------------------------

// Join a socket to an ephemeral room: presence, alias, colour, broadcasts.
async function joinSocketToRoom(io, socket, room, alias) {
  const code = room.code;
  socket.join(code);
  socket.data.rooms.add(code);

  await addUserToRoom(code, socket.id);
  await setAlias(code, socket.id, alias);
  const color = generateColor();
  await setColor(code, socket.id, color);

  // Keep the DB currentUsers roughly in sync (best-effort).
  await Room.updateOne(
    { _id: room._id },
    { $addToSet: { currentUsers: socket.id } }
  ).catch(() => {});

  const users = await getRoomUsers(code);
  socket.to(code).emit(SOCKET_EVENTS.USER_JOINED, {
    alias,
    color,
    userCount: users.length,
  });
}

// Remove a socket from an ephemeral room and broadcast user_left.
async function leaveEphemeralRoom(io, socket, code, silent = false) {
  const alias = await getAlias(code, socket.id);
  await removeUserFromRoom(code, socket.id);
  await removeAlias(code, socket.id);
  await Room.updateOne({ code }, { $pull: { currentUsers: socket.id } }).catch(() => {});

  socket.leave(code);
  socket.data.rooms.delete(code);

  if (!silent && alias) {
    const users = await getRoomUsers(code);
    socket.to(code).emit(SOCKET_EVENTS.USER_LEFT, {
      alias,
      userCount: users.length,
    });
  }
}
