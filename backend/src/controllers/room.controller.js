// Room controller — REST surface for rooms.
//
//  - Ephemeral: create (get a code), validate a code before joining.
//  - Permanent: list a user's DM rooms, delete a conversation (your side only).
//
// Realtime room lifecycle (join/leave/messages/end) is handled over Socket.io,
// not here. This controller only covers the REST bits.

import { Room } from '../models/room.model.js';
import { Message } from '../models/message.model.js';
import { User } from '../models/user.model.js';
import { ApiError } from '../utils/ApiError.js';
import { ApiResponse } from '../utils/ApiResponse.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { generateRoomCode } from '../utils/codeGenerator.js';
import { ROOM } from '../constants.js';

// POST /api/v1/rooms  — create an ephemeral room (guests allowed).
// Body: { name, maxUsers, isLocked, passHint, ttlSeconds, createdBy }
export const createEphemeralRoom = asyncHandler(async (req, res) => {
  const {
    name,
    maxUsers = ROOM.DEFAULT_MAX_USERS,
    isLocked = false,
    passHint = null,
    ttlSeconds = ROOM.DEFAULT_TTL,
    createdBy,
  } = req.body;

  if (!createdBy) throw new ApiError(400, 'createdBy (alias) is required');
  if (maxUsers < 2 || maxUsers > 10) {
    throw new ApiError(400, 'maxUsers must be between 2 and 10');
  }

  // Generate a unique code (retry on the rare collision).
  let code;
  for (let attempt = 0; attempt < 5; attempt++) {
    code = generateRoomCode();
    // eslint-disable-next-line no-await-in-loop
    const clash = await Room.exists({ code });
    if (!clash) break;
    code = null;
  }
  if (!code) throw new ApiError(500, 'Could not allocate a unique room code');

  const room = await Room.create({
    type: 'ephemeral',
    name: name || 'Cypher Room',
    createdBy,
    createdByUserId: req.user?._id || null, // set when the host is logged in
    code,
    maxUsers,
    isLocked,
    passHashHint: passHint,
    inactivityTTL: ttlSeconds,
    // lastActivityAt holds the FUTURE expiry timestamp (see room.model.js).
    lastActivityAt: new Date(Date.now() + ttlSeconds * 1000),
  });

  return res.status(201).json(
    new ApiResponse(
      201,
      {
        roomId: room._id,
        code: room.code,
        name: room.name,
        maxUsers: room.maxUsers,
        isLocked: room.isLocked,
        expiresAt: room.lastActivityAt,
      },
      'Room created'
    )
  );
});

// GET /api/v1/rooms/permanent  — a user's permanent DM rooms (auth).
// Placed before the /:code route in the router so "permanent" isn't read as a
// code.
export const getPermanentRooms = asyncHandler(async (req, res) => {
  const rooms = await Room.find({
    type: 'permanent',
    participants: req.user._id,
  })
    .populate(
      'participants',
      'displayName username avatar isOnline lastSeenAt showOnlineStatus showLastSeen'
    )
    .sort({ updatedAt: -1 });

  // For each room, attach the last VISIBLE message's metadata (never content).
  const withPreview = await Promise.all(
    rooms.map(async (room) => {
      // The most recent message this user hasn't deleted.
      const last = await Message.findOne({
        roomId: room._id,
        deletedFor: { $ne: req.user._id },
      })
        .sort({ createdAt: -1 })
        .select('type senderAlias createdAt');

      // Total messages in the room (regardless of who deleted what).
      const totalCount = await Message.countDocuments({ roomId: room._id });

      // Instagram-style delete: if the user cleared this conversation (there
      // ARE messages, but none visible to them), hide it from the list until a
      // new message arrives. A brand-new room (no messages yet) still shows so
      // the pair can start chatting.
      if (totalCount > 0 && !last) return null;

      // Show only the OTHER participant to the client, presence masked per
      // their privacy prefs.
      const otherDoc = room.participants.find(
        (p) => String(p._id) !== String(req.user._id)
      );
      let other = otherDoc;
      if (otherDoc) {
        other = otherDoc.toObject();
        if (other.showOnlineStatus === false) other.isOnline = false;
        if (other.showLastSeen === false) other.lastSeenAt = null;
        delete other.showOnlineStatus;
        delete other.showLastSeen;
      }

      return {
        roomId: room._id,
        name: room.name,
        other,
        lastMessageAt: last?.createdAt || room.updatedAt,
        // Preview is intentionally content-free.
        lastMessagePreview: last ? 'New message' : null,
      };
    })
  );

  return res
    .status(200)
    .json(new ApiResponse(200, { rooms: withPreview.filter(Boolean) }));
});

// GET /api/v1/rooms/:code  — validate an ephemeral code + return join config.
export const getRoomByCode = asyncHandler(async (req, res) => {
  const code = req.params.code.toUpperCase();
  const room = await Room.findOne({ type: 'ephemeral', code });
  if (!room) throw new ApiError(404, 'Room not found or has expired');

  // Return only what a joiner needs — never internal state.
  return res.status(200).json(
    new ApiResponse(200, {
      roomId: room._id,
      code: room.code,
      name: room.name,
      maxUsers: room.maxUsers,
      isLocked: room.isLocked,
      passHint: room.passHashHint,
      currentCount: room.currentUsers.length,
      expiresAt: room.lastActivityAt,
    })
  );
});

// DELETE /api/v1/rooms/permanent/:roomId  — delete conversation (your side).
// This removes the user's participation + wrapped key + hides existing messages
// from them. The other participant's copy is untouched (soft, per-user delete).
export const deletePermanentRoom = asyncHandler(async (req, res) => {
  const { roomId } = req.params;
  const room = await Room.findById(roomId);
  if (!room || room.type !== 'permanent') {
    throw new ApiError(404, 'Conversation not found');
  }
  if (!room.participants.some((p) => String(p) === String(req.user._id))) {
    throw new ApiError(403, 'You are not part of this conversation');
  }

  // Drop this user's wrapped key so they can no longer decrypt anything.
  await User.findByIdAndUpdate(req.user._id, {
    $pull: { roomKeys: { roomId: room._id } },
  });

  // Hide all existing messages from this user only (soft, your-side delete).
  await Message.updateMany(
    { roomId: room._id },
    { $addToSet: { deletedFor: req.user._id } }
  );

  return res
    .status(200)
    .json(new ApiResponse(200, {}, 'Conversation deleted on your side'));
});
