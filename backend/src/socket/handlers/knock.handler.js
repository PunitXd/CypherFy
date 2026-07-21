// Knock handler — the "request to enter a locked room" flow.
//
//  1. A joiner emits `knock` with the room code + their alias.
//  2. The host receives `knock_request` { alias, socketId }.
//  3. Host emits `admit_user` or `reject_user` with that socketId.
//  4. The knocker gets `knock_admitted` (then joins) or `knock_rejected`.

import { Room } from '../../models/room.model.js';
import { User } from '../../models/user.model.js';
import {
  setKnock,
  getKnock,
  deleteKnock,
  getAllAliases,
  getAlias,
  addAdmitted,
} from '../../services/redis.service.js';
import { sendKnockNotification } from '../../services/fcm.service.js';
import { SOCKET_EVENTS, ERROR_CODES } from '../../constants.js';
import { validatePayload } from '../../middlewares/validate.middleware.js';
import { socketSchemas } from '../../validators/socket.schemas.js';

export const registerKnockHandlers = (io, socket) => {
  // ---- knock ----------------------------------------------------------
  socket.on(SOCKET_EVENTS.KNOCK, async (rawPayload) => {
    const v = validatePayload(socketSchemas.knock, rawPayload);
    if (!v.ok) return;
    try {
      const { code: rawCode, alias } = v.data;
      const code = rawCode.toUpperCase();

      const room = await Room.findOne({ code, type: 'ephemeral' });
      if (!room) {
        return socket.emitError(ERROR_CODES.ROOM_NOT_FOUND, 'Room not found');
      }

      // Record the knock (auto-expires in 5 min).
      await setKnock(code, socket.id, alias);

      // Find the host's socket by matching the room's createdBy alias.
      const aliases = await getAllAliases(code); // socketId → alias
      const hostSocketId = Object.keys(aliases).find(
        (sid) => aliases[sid] === room.createdBy
      );

      if (hostSocketId) {
        io.to(hostSocketId).emit(SOCKET_EVENTS.KNOCK_REQUEST, {
          alias,
          socketId: socket.id,
        });
      } else if (room.createdByUserId) {
        // Host isn't in the room right now → wake them with a push so they can
        // come back and admit the knocker (the knock also waits in Redis).
        const host = await User.findById(room.createdByUserId).select('fcmTokens');
        for (const token of host?.fcmTokens || []) {
          sendKnockNotification(token, alias, code);
        }
      }
    } catch (err) {
      console.error('knock error:', err.message);
    }
  });

  // ---- admit_user (host only) -----------------------------------------
  socket.on(SOCKET_EVENTS.ADMIT_USER, async (rawPayload) => {
    const v = validatePayload(socketSchemas.admitUser, rawPayload);
    if (!v.ok) return;
    try {
      const { knockSocketId, code: rawCode } = v.data;
      const code = rawCode.toUpperCase();

      const room = await Room.findOne({ code, type: 'ephemeral' });
      if (!room) return;

      // Verify the caller is the host.
      const myAlias = await getAlias(code, socket.id);
      if (room.createdBy !== myAlias) {
        return socket.emitError(ERROR_CODES.NOT_HOST, 'Only the host can admit users');
      }

      const knockAlias = await getKnock(code, knockSocketId);
      if (!knockAlias) return; // knock expired or already handled

      await deleteKnock(code, knockSocketId);
      // Record the admission so the follow-up join_room bypasses the lock.
      await addAdmitted(code, knockSocketId);
      // Tell the knocker they're in — their client then emits join_room.
      io.to(knockSocketId).emit(SOCKET_EVENTS.KNOCK_ADMITTED, {
        code,
        alias: knockAlias,
      });
    } catch (err) {
      console.error('admit_user error:', err.message);
    }
  });

  // ---- reject_user (host only) ----------------------------------------
  socket.on(SOCKET_EVENTS.REJECT_USER, async (rawPayload) => {
    const v = validatePayload(socketSchemas.rejectUser, rawPayload);
    if (!v.ok) return;
    try {
      const { knockSocketId, code: rawCode } = v.data;
      const code = rawCode.toUpperCase();

      const room = await Room.findOne({ code, type: 'ephemeral' });
      if (!room) return;

      const myAlias = await getAlias(code, socket.id);
      if (room.createdBy !== myAlias) {
        return socket.emitError(ERROR_CODES.NOT_HOST, 'Only the host can reject users');
      }

      await deleteKnock(code, knockSocketId);
      io.to(knockSocketId).emit(SOCKET_EVENTS.KNOCK_REJECTED, {});
    } catch (err) {
      console.error('reject_user error:', err.message);
    }
  });
};
