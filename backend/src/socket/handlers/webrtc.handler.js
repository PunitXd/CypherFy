// Call signalling handler — the control plane for voice/video calls.
//
// The server NEVER touches media. It runs the call *setup* state machine
// (ring / accept / reject / cancel / leave / busy) and relays SDP + ICE between
// peers by socket id. Actual audio/video flows peer-to-peer over a mesh of
// RTCPeerConnections (DTLS-SRTP encrypted), or via the configured TURN relay.
//
// A call is a set of member sockets tied to a room *channel*:
//   - DM:    channel = `perm:<roomId>`  (ring the other participant on user:<id>)
//   - group: channel = <ROOMCODE>       (ring everyone already in the socket room)
// Mesh is glare-free: whoever *joins* offers to every peer already present.

import { randomUUID } from 'crypto';
import { SOCKET_EVENTS, ERROR_CODES } from '../../constants.js';
import { getIceConfig } from '../../services/ice.service.js';
import { Room } from '../../models/room.model.js';
import { User } from '../../models/user.model.js';
import { sendCallNotification } from '../../services/fcm.service.js';
import { isMuted } from '../../utils/mute.js';
import {
  createCall,
  getCallMeta,
  addCallMember,
  removeCallMember,
  getCallMembers,
  setChannelCall,
  getChannelCall,
  delChannelCall,
  setUserInCall,
  clearUserInCall,
  reapCall as reap,
  getAlias,
} from '../../services/redis.service.js';
import { validatePayload } from '../../middlewares/validate.middleware.js';
import { socketSchemas } from '../../validators/socket.schemas.js';

// A group channel is an ephemeral room code (DMs use the `perm:<id>` namespace).
const isGroupChannel = (channel) => !channel.startsWith('perm:');

// Who is this socket, for the ring card + roster? Account users resolve to their
// profile; anonymous ephemeral guests resolve to their room alias.
const identify = async (socket, channel) => {
  if (isGroupChannel(channel)) {
    const alias = await getAlias(channel, socket.id);
    return {
      userId: socket.data.userId ? String(socket.data.userId) : socket.id,
      name: alias || 'Guest',
      avatar: null,
    };
  }
  const u = socket.data.userId
    ? await User.findById(socket.data.userId).select('displayName username avatar')
    : null;
  return {
    userId: String(socket.data.userId || socket.id),
    name: u?.displayName || u?.username || 'Someone',
    avatar: u?.avatar || null,
  };
};

// Build the "group call in progress" payload (callId, type, live head-count, and
// when it started) for the rejoin banner.
const groupActivePayload = async (channel, callId) => {
  const meta = await getCallMeta(callId);
  if (!meta) return null;
  const members = await getCallMembers(callId);
  return {
    callId,
    callType: meta.callType,
    channel,
    count: Object.keys(members).length,
    startedAt: Number(meta.startedAt) || null,
  };
};

// Broadcast the current group-call state to everyone in the room channel.
const broadcastGroupState = async (io, channel, callId) => {
  const payload = await groupActivePayload(channel, callId);
  if (payload) io.to(channel).emit(SOCKET_EVENTS.CALL_GROUP_ACTIVE, payload);
};

// Remove a socket from a call, notify remaining peers, and reap an empty session.
const leaveCall = async (io, socket, callId) => {
  const meta = await getCallMeta(callId);
  if (socket.data) socket.data.callId = null;
  if (!meta) return;

  await removeCallMember(callId, socket.id);
  if (socket.data?.userId) await clearUserInCall(String(socket.data.userId));

  const members = await getCallMembers(callId);
  for (const sid of Object.keys(members)) {
    io.to(sid).emit(SOCKET_EVENTS.CALL_PEER_LEFT, { socketId: socket.id, callId });
  }
  if (Object.keys(members).length === 0) {
    await reap(callId, meta.channel, members);
    // Group call fully drained → clear the rejoin banner for everyone in the room.
    if (isGroupChannel(meta.channel)) {
      io.to(meta.channel).emit(SOCKET_EVENTS.CALL_GROUP_ENDED, { channel: meta.channel });
    }
  } else if (isGroupChannel(meta.channel)) {
    // Someone left but the call continues → refresh the banner head-count.
    await broadcastGroupState(io, meta.channel, callId);
  }
};

export const registerWebrtcHandlers = (io, socket) => {
  // ---- call:start — begin (or join) a call and ring the other side ----
  socket.on(SOCKET_EVENTS.CALL_START, async (rawPayload, cb) => {
    const v = validatePayload(socketSchemas.callStart, rawPayload);
    if (!v.ok) {
      if (typeof cb === 'function') cb({ ok: false, error: v.error });
      return socket.emitError('BAD_PAYLOAD', v.error[0]?.message || 'Invalid call request');
    }
    const { roomId, code, callType } = v.data;
    try {
      const isGroup = Boolean(code);
      // DMs are account-only; group (ephemeral) calls allow anonymous guests.
      if (!isGroup && !socket.data.userId) {
        return socket.emitError(ERROR_CODES.UNAUTHORIZED, 'Login required to call');
      }
      const channel = isGroup ? String(code).toUpperCase() : `perm:${roomId}`;
      const from = await identify(socket, channel);

      // DM: resolve the other participant and short-circuit if they're busy.
      let otherId = null;
      if (!isGroup) {
        const room = await Room.findById(roomId).select('participants type');
        if (!room || room.type !== 'permanent') {
          return socket.emitError(ERROR_CODES.ROOM_NOT_FOUND, 'Conversation not found');
        }
        otherId = room.participants.map(String).find((p) => p !== from.userId);
        // No busy check — if the callee is already in a call they still get rung
        // (call-waiting): their client offers Accept (switch) or Decline.
      }

      // Join an in-progress call on this channel, or open a new one. A stale
      // channel pointer (call reaped but the pointer lingered) would otherwise
      // wedge every future call on this channel, so verify it still exists.
      let callId = await getChannelCall(channel);
      if (callId && !(await getCallMeta(callId))) {
        await delChannelCall(channel);
        callId = null;
      }
      if (!callId) {
        callId = randomUUID();
        await createCall(callId, { channel, callType, callerUserId: from.userId });
        await setChannelCall(channel, callId);
      }
      await addCallMember(callId, socket.id, { userId: from.userId, name: from.name });
      if (socket.data.userId) await setUserInCall(String(socket.data.userId), callId);
      socket.data.callId = callId;

      socket.emit(SOCKET_EVENTS.CALL_STARTED, {
        callId,
        callType: callType || 'audio',
        channel,
        isGroup,
        ...getIceConfig(),
      });
      if (typeof cb === 'function') cb({ ok: true, callId });

      const invite = { callId, from, callType: callType || 'audio', channel, isGroup };
      if (isGroup) {
        socket.to(channel).emit(SOCKET_EVENTS.CALL_INCOMING, invite);
        // Persistent "a call is happening here" signal for the whole room (incl.
        // the starter) so everyone not in the call can see a rejoin banner.
        await broadcastGroupState(io, channel, callId);
      } else if (otherId) {
        const u = await User.findById(otherId)
          .select('fcmTokens receiveCalls mutedUsers');
        // Full "do not disturb" for calls → don't ring at all; tell the caller.
        if (u && u.receiveCalls === false) {
          socket.emit(SOCKET_EVENTS.CALL_ENDED, { callId, reason: 'unavailable' });
          await reap(callId, channel);
          return;
        }
        // Per-user call mute: the callee silenced THIS caller. Deliver nothing
        // (no ring, no push) — invisibly, so the caller just rings out and gets
        // "no answer" rather than learning they've been muted.
        if (!isMuted(u, from.userId, 'callsUntil')) {
          io.to(`user:${otherId}`).emit(SOCKET_EVENTS.CALL_INCOMING, invite);
          // No live socket for the callee → wake the device with a call push.
          const live = await io.in(`user:${otherId}`).fetchSockets();
          if (live.length === 0) {
            for (const t of u?.fcmTokens || []) {
              sendCallNotification(t, from, callId, callType || 'audio');
            }
          }
        }
      }
    } catch (err) {
      console.error('call:start error:', err.message);
    }
  });

  // ---- call:accept — join the call; mesh with everyone already present ----
  socket.on(SOCKET_EVENTS.CALL_ACCEPT, async (rawPayload) => {
    const v = validatePayload(socketSchemas.callId, rawPayload);
    if (!v.ok) return socket.emitError('BAD_PAYLOAD', v.error[0]?.message || 'Invalid call id');
    const { callId } = v.data;
    try {
      const meta = await getCallMeta(callId);
      if (!meta) return socket.emit(SOCKET_EVENTS.CALL_ENDED, { callId });

      // Snapshot peers BEFORE adding ourselves — we offer to each of them.
      const existing = await getCallMembers(callId);
      const me = await identify(socket, meta.channel);

      await addCallMember(callId, socket.id, { userId: me.userId, name: me.name });
      if (socket.data.userId) await setUserInCall(String(socket.data.userId), callId);
      socket.data.callId = callId;

      socket.emit(SOCKET_EVENTS.CALL_ACCEPTED, {
        callId,
        callType: meta.callType,
        channel: meta.channel,
        ...getIceConfig(),
        peers: Object.entries(existing).map(([socketId, m]) => ({
          socketId,
          userId: m.userId,
          name: m.name,
        })),
      });
      for (const sid of Object.keys(existing)) {
        io.to(sid).emit(SOCKET_EVENTS.CALL_PEER_JOINED, {
          socketId: socket.id,
          userId: me.userId,
          name: me.name,
        });
      }
      // Group call gained a member → refresh the rejoin banner's head-count.
      if (isGroupChannel(meta.channel)) {
        await broadcastGroupState(io, meta.channel, callId);
      }
    } catch (err) {
      console.error('call:accept error:', err.message);
    }
  });

  // ---- call:reject — decline a ringing call ----
  socket.on(SOCKET_EVENTS.CALL_REJECT, async (rawPayload) => {
    const v = validatePayload(socketSchemas.callId, rawPayload);
    if (!v.ok) return;
    const { callId } = v.data;
    try {
      const meta = await getCallMeta(callId);
      if (!meta) return;
      const members = await getCallMembers(callId);

      // Group call: a ringing invitee declined. The call goes ON for everyone
      // already in it — just tell them "X declined" (info only), never end it.
      if (isGroupChannel(meta.channel)) {
        const me = await identify(socket, meta.channel);
        for (const sid of Object.keys(members)) {
          io.to(sid).emit(SOCKET_EVENTS.CALL_PEER_DECLINED, {
            name: me.name,
            callId,
          });
        }
        return;
      }

      // 1:1 call: the callee declined → end the caller's call.
      const who = String(socket.data.userId || '');
      for (const sid of Object.keys(members)) {
        io.to(sid).emit(SOCKET_EVENTS.CALL_REJECTED, { userId: who, callId });
      }
      // Only the caller is left → reap (also clears their in-call marker).
      if (Object.keys(members).length <= 1) {
        await reap(callId, meta.channel, members);
      }
    } catch (err) {
      console.error('call:reject error:', err.message);
    }
  });

  // ---- call:cancel — caller aborts before it's answered ----
  socket.on(SOCKET_EVENTS.CALL_CANCEL, async (rawPayload) => {
    const v = validatePayload(socketSchemas.callId, rawPayload);
    if (!v.ok) return;
    const { callId } = v.data;
    try {
      const meta = await getCallMeta(callId);
      if (!meta) return;
      if (meta.channel.startsWith('perm:')) {
        const roomId = meta.channel.slice('perm:'.length);
        const room = await Room.findById(roomId).select('participants');
        const otherId = room?.participants
          ?.map(String)
          .find((p) => p !== String(socket.data.userId));
        if (otherId) io.to(`user:${otherId}`).emit(SOCKET_EVENTS.CALL_CANCELLED, { callId });
      } else {
        socket.to(meta.channel).emit(SOCKET_EVENTS.CALL_CANCELLED, { callId });
      }
      await leaveCall(io, socket, callId);
    } catch (err) {
      console.error('call:cancel error:', err.message);
    }
  });

  // ---- call:leave — hang up / leave an active call ----
  socket.on(SOCKET_EVENTS.CALL_LEAVE, async (rawPayload) => {
    const v = validatePayload(socketSchemas.callId, rawPayload);
    if (!v.ok) return;
    await leaveCall(io, socket, v.data.callId).catch((e) =>
      console.error('call:leave error:', e.message)
    );
  });

  // ---- call:group_state — is a group call ongoing in this room? (rejoin banner)
  socket.on(SOCKET_EVENTS.CALL_GROUP_STATE, async (rawPayload) => {
    const v = validatePayload(socketSchemas.callGroupState, rawPayload);
    if (!v.ok) return;
    try {
      const { code } = v.data;
      const channel = String(code).toUpperCase();
      const callId = await getChannelCall(channel);
      const payload = callId ? await groupActivePayload(channel, callId) : null;
      if (payload) {
        socket.emit(SOCKET_EVENTS.CALL_GROUP_ACTIVE, payload);
      } else {
        socket.emit(SOCKET_EVENTS.CALL_GROUP_ENDED, { channel });
      }
    } catch (err) {
      console.error('call:group_state error:', err.message);
    }
  });

  // ---- Mesh relays (carry callId + targetSocketId; server just forwards) ----
  socket.on(SOCKET_EVENTS.WEBRTC_OFFER, (rawPayload) => {
    const v = validatePayload(socketSchemas.webrtcOffer, rawPayload);
    if (!v.ok) return;
    const { offer, targetSocketId, callId } = v.data;
    io.to(targetSocketId).emit(SOCKET_EVENTS.WEBRTC_OFFER, {
      offer,
      callId,
      fromSocketId: socket.id,
    });
  });

  socket.on(SOCKET_EVENTS.WEBRTC_ANSWER, (rawPayload) => {
    const v = validatePayload(socketSchemas.webrtcAnswer, rawPayload);
    if (!v.ok) return;
    const { answer, targetSocketId, callId } = v.data;
    io.to(targetSocketId).emit(SOCKET_EVENTS.WEBRTC_ANSWER, {
      answer,
      callId,
      fromSocketId: socket.id,
    });
  });

  socket.on(SOCKET_EVENTS.ICE_CANDIDATE, (rawPayload) => {
    const v = validatePayload(socketSchemas.iceCandidate, rawPayload);
    if (!v.ok) return;
    const { candidate, targetSocketId, callId } = v.data;
    io.to(targetSocketId).emit(SOCKET_EVENTS.ICE_CANDIDATE, {
      candidate,
      callId,
      fromSocketId: socket.id,
    });
  });

  // ---- Leave any active call when the socket drops ----
  socket.on('disconnect', () => {
    if (socket.data?.callId) {
      leaveCall(io, socket, socket.data.callId).catch(() => {});
    }
  });
};
