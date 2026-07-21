// Message handler — send text, send file, react, delete.
//
// Everything stored is ciphertext. The server persists { ciphertext, iv } for
// text and { blobName, encMeta, metaIv, size } for files, then rebroadcasts to
// the room. It never logs or inspects content.

import { Room } from '../../models/room.model.js';
import { Message } from '../../models/message.model.js';
import { User } from '../../models/user.model.js';
import {
  getAlias,
  getRoomUsers,
  shouldSendFcm,
} from '../../services/redis.service.js';
import { sendMessageNotification } from '../../services/fcm.service.js';
import { isMuted } from '../../utils/mute.js';
import { touchRoom } from './room.handler.js';
import { SOCKET_EVENTS, ERROR_CODES } from '../../constants.js';
import { validatePayload } from '../../middlewares/validate.middleware.js';
import { socketSchemas } from '../../validators/socket.schemas.js';

// Resolve the socket.io channel + a Room doc for a given payload. Ephemeral
// rooms are addressed by `code`, permanent by `roomId`.
async function resolveTarget(socket, payload) {
  if (payload.code) {
    const code = payload.code.toUpperCase();
    const room = await Room.findOne({ code, type: 'ephemeral' });
    return { room, channel: code, code };
  }
  const room = await Room.findById(payload.roomId);
  return { room, channel: room ? `perm:${room._id}` : null, code: null };
}

export const registerMessageHandlers = (io, socket) => {
  // ---- send_message (text) --------------------------------------------
  socket.on(SOCKET_EVENTS.SEND_MESSAGE, async (rawPayload) => {
    const v = validatePayload(socketSchemas.sendMessage, rawPayload);
    if (!v.ok) return socket.emitError('BAD_PAYLOAD', v.error[0]?.message || 'Invalid message');
    const payload = v.data;
    try {
      const { ciphertext, iv, replyTo = null } = payload;

      const { room, channel, code } = await resolveTarget(socket, payload);
      if (!room) return socket.emitError(ERROR_CODES.ROOM_NOT_FOUND, 'Room not found');

      const senderAlias = code
        ? (await getAlias(code, socket.id)) || 'Unknown'
        : socket.data.displayName || 'Unknown';

      const message = await Message.create({
        roomId: room._id,
        type: 'text',
        senderAlias,
        senderId: socket.data.userId || null,
        ciphertext,
        iv,
        replyTo,
      });

      io.to(channel).emit(SOCKET_EVENTS.NEW_MESSAGE, serialize(message));

      // Ephemeral: reset the inactivity clock.
      if (code) await touchRoom(io, code, room.inactivityTTL);

      // Permanent: nudge every participant's home screen + FCM the offline ones.
      if (!code) {
        pingParticipants(io, room);
        await notifyOfflineParticipants(room, socket, senderAlias);
      }
    } catch (err) {
      console.error('send_message error:', err.message);
      socket.emitError('SERVER', 'Failed to send message');
    }
  });

  // ---- send_file ------------------------------------------------------
  socket.on(SOCKET_EVENTS.SEND_FILE, async (rawPayload) => {
    const v = validatePayload(socketSchemas.sendFile, rawPayload);
    if (!v.ok) return socket.emitError('BAD_PAYLOAD', v.error[0]?.message || 'Invalid file message');
    const payload = v.data;
    try {
      const { blobName, iv, encMeta, metaIv, size, replyTo = null } = payload;

      const { room, channel, code } = await resolveTarget(socket, payload);
      if (!room) return socket.emitError(ERROR_CODES.ROOM_NOT_FOUND, 'Room not found');

      const senderAlias = code
        ? (await getAlias(code, socket.id)) || 'Unknown'
        : socket.data.displayName || 'Unknown';

      const message = await Message.create({
        roomId: room._id,
        type: 'file',
        senderAlias,
        senderId: socket.data.userId || null,
        blobName,
        iv,
        encMeta,
        metaIv,
        size,
        replyTo,
      });

      io.to(channel).emit(SOCKET_EVENTS.NEW_MESSAGE, serialize(message));

      if (code) await touchRoom(io, code, room.inactivityTTL);
      if (!code) {
        pingParticipants(io, room);
        await notifyOfflineParticipants(room, socket, senderAlias);
      }
    } catch (err) {
      console.error('send_file error:', err.message);
      socket.emitError('SERVER', 'Failed to send file');
    }
  });

  // ---- add_reaction ---------------------------------------------------
  socket.on(SOCKET_EVENTS.ADD_REACTION, async (rawPayload) => {
    const v = validatePayload(socketSchemas.addReaction, rawPayload);
    if (!v.ok) return socket.emitError('BAD_PAYLOAD', v.error[0]?.message || 'Invalid reaction');
    try {
      const { messageId, emoji } = v.data;

      const message = await Message.findById(messageId);
      if (!message) return;

      const current = message.reactions.get(emoji) || 0;
      message.reactions.set(emoji, current + 1);
      await message.save();

      const channel = await channelForRoom(message.roomId);
      io.to(channel).emit(SOCKET_EVENTS.REACTION_UPDATED, {
        messageId,
        emoji,
        count: message.reactions.get(emoji),
      });
    } catch (err) {
      console.error('add_reaction error:', err.message);
    }
  });

  // ---- delete_message (soft, sender's side) ---------------------------
  socket.on(SOCKET_EVENTS.DELETE_MESSAGE, async (rawPayload) => {
    const v = validatePayload(socketSchemas.deleteMessage, rawPayload);
    if (!v.ok) return socket.emitError('BAD_PAYLOAD', v.error[0]?.message || 'Invalid request');
    try {
      const { messageId } = v.data;

      const message = await Message.findById(messageId);
      if (!message) return;

      // Only the original sender may delete their message.
      const isSender =
        (socket.data.userId &&
          String(message.senderId) === String(socket.data.userId)) ||
        false;
      // For anonymous ephemeral rooms, allow delete if the socket's current
      // alias matches the sender alias.
      let aliasMatch = false;
      const channel = await channelForRoom(message.roomId);
      if (!isSender && !channel.startsWith('perm:')) {
        const myAlias = await getAlias(channel, socket.id);
        aliasMatch = myAlias && myAlias === message.senderAlias;
      }
      if (!isSender && !aliasMatch) {
        return socket.emitError(ERROR_CODES.UNAUTHORIZED, 'Not your message');
      }

      if (socket.data.userId) {
        message.deletedFor.addToSet(socket.data.userId);
        await message.save();
      } else {
        // Anonymous: hard delete for everyone (ephemeral, no per-user copies).
        await Message.deleteOne({ _id: messageId });
      }

      io.to(channel).emit(SOCKET_EVENTS.MESSAGE_DELETED, { messageId });
    } catch (err) {
      console.error('delete_message error:', err.message);
    }
  });

  // ---- message_seen — mark delivered/read up to a point ----------------
  // Payload: { code?|roomId?, upToId?, state: 'delivered'|'read' }. When upToId
  // is given, everything in that room up to its timestamp is covered; otherwise
  // everything up to now (used by the home screen on a dm_activity ping). The
  // caller's own messages are never marked. Broadcasts a receipt_update so the
  // original senders can advance their ticks.
  socket.on(SOCKET_EVENTS.MESSAGE_SEEN, async (rawPayload) => {
    const v = validatePayload(socketSchemas.messageSeen, rawPayload);
    if (!v.ok) return;
    try {
      const { code, roomId, upToId, state } = v.data;

      // Resolve the room, the cutoff timestamp, the reader's identifier, and a
      // filter that excludes the reader's own messages.
      let rid;
      let atDate;
      if (upToId) {
        const anchor = await Message.findById(upToId).select('roomId createdAt');
        if (!anchor) return;
        rid = anchor.roomId;
        atDate = anchor.createdAt;
      } else {
        rid = code
          ? (await Room.findOne({ code: code.toUpperCase(), type: 'ephemeral' }).select('_id'))?._id
          : roomId;
        atDate = new Date();
      }
      if (!rid) return;

      let id;
      let senderFilter;
      if (code) {
        id = await getAlias(code.toUpperCase(), socket.id);
        if (!id) return; // not a member of this room
        senderFilter = { senderAlias: { $ne: id } };
      } else {
        if (!socket.data.userId) return;
        id = String(socket.data.userId);
        senderFilter = { senderId: { $ne: socket.data.userId } };
      }

      const setOps =
        state === 'read'
          ? { $addToSet: { deliveredTo: id, readBy: id } }
          : { $addToSet: { deliveredTo: id } };

      await Message.updateMany(
        { roomId: rid, createdAt: { $lte: atDate }, ...senderFilter },
        setOps
      );

      const channel = code ? code.toUpperCase() : `perm:${rid}`;
      socket.to(channel).emit(SOCKET_EVENTS.RECEIPT_UPDATE, {
        by: id,
        state,
        upToAt: atDate,
        roomId: String(rid),
      });
    } catch (err) {
      console.error('message_seen error:', err.message);
    }
  });
};

// Serialise a message doc into the new_message wire shape.
function serialize(m) {
  return {
    messageId: m._id,
    roomId: m.roomId,
    type: m.type,
    senderAlias: m.senderAlias,
    senderId: m.senderId,
    ciphertext: m.ciphertext,
    iv: m.iv,
    blobName: m.blobName,
    encMeta: m.encMeta,
    metaIv: m.metaIv,
    size: m.size,
    replyTo: m.replyTo,
    reactions: Object.fromEntries(m.reactions || []),
    deliveredTo: m.deliveredTo || [],
    readBy: m.readBy || [],
    createdAt: m.createdAt,
  };
}

// Determine the broadcast channel for a room id (ephemeral code vs perm:id).
async function channelForRoom(roomId) {
  const room = await Room.findById(roomId).select('type code');
  if (room?.type === 'ephemeral') return room.code;
  return `perm:${roomId}`;
}

// Content-free live nudge to every participant's personal channel so a home
// screen that isn't inside the chat still updates instantly (e.g. a deleted
// conversation reappearing when the other person messages again).
function pingParticipants(io, room) {
  for (const p of room.participants) {
    io.to(`user:${p}`).emit(SOCKET_EVENTS.DM_ACTIVITY, {
      roomId: String(room._id),
    });
  }
}

// Content-free FCM push to permanent-room participants who are offline.
async function notifyOfflineParticipants(room, socket, senderAlias) {
  const others = room.participants.filter(
    (p) => String(p) !== String(socket.data.userId)
  );
  for (const participantId of others) {
    // Is this participant present in the room's socket channel right now?
    const sockets = await socket.nsp.in(`user:${participantId}`).fetchSockets();
    const online = sockets.length > 0;
    if (online) continue; // they'll get the realtime new_message instead

    const user = await User.findById(participantId).select('fcmTokens mutedUsers');
    if (!user) continue;
    // Respect a per-user message mute: this participant silenced the sender.
    if (isMuted(user, socket.data.userId, 'messagesUntil')) continue;
    for (const token of user.fcmTokens) {
      // Only push if they've been gone long enough (spec: > 30s).
      const socketId = sockets[0]?.id;
      const ok = socketId ? await shouldSendFcm(socketId) : true;
      if (ok) sendMessageNotification(token, senderAlias, room._id);
    }
  }
}
