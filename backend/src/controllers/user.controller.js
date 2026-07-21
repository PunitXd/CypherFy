// User controller — profile, search, contacts, and the chat-request lifecycle.
//
// Chat requests live here (the spec has no dedicated requests controller). When
// a request is accepted a permanent Room is created; both participants derive
// the room key locally from the room id (PBKDF2), so the server stores no keys.

import mongoose from 'mongoose';
import { User } from '../models/user.model.js';
import { Room } from '../models/room.model.js';
import { Message } from '../models/message.model.js';
import { ChatRequest } from '../models/chatRequest.model.js';
import { ApiError } from '../utils/ApiError.js';
import { ApiResponse } from '../utils/ApiResponse.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { sendChatRequestNotification } from '../services/fcm.service.js';
import { deleteBlobsByRoom } from '../services/r2.service.js';
import { getIO } from '../socket/index.js';
import { SOCKET_EVENTS } from '../constants.js';

// ---- Profile ------------------------------------------------------------

// GET /api/v1/users/me
export const getMe = asyncHandler(async (req, res) => {
  return res
    .status(200)
    .json(new ApiResponse(200, { user: req.user.toSafeObject() }));
});

// PATCH /api/v1/users/me  — update displayName / bio / privacy prefs
// Users may change their @username at most once every 30 days.
const USERNAME_COOLDOWN_DAYS = 30;
const USERNAME_COOLDOWN_MS = USERNAME_COOLDOWN_DAYS * 24 * 60 * 60 * 1000;

export const updateMe = asyncHandler(async (req, res) => {
  const { displayName, bio, username, showOnlineStatus, showLastSeen, receiveCalls } =
    req.body;

  // verifyJWT strips passwordHash, so saving req.user directly would trip the
  // pre('validate') "needs a credential" hook. Re-fetch the full document.
  const me = await User.findById(req.user._id);
  if (!me) throw new ApiError(404, 'User not found');

  // ---- Username change (rate-limited, unique, validated) ----
  if (username !== undefined) {
    const next = String(username).trim().toLowerCase();
    if (next !== me.username) {
      if (!/^[a-z0-9_]{3,20}$/.test(next)) {
        throw new ApiError(
          400,
          'Username must be 3–20 characters using lowercase letters, numbers, or underscores'
        );
      }
      // 30-day cooldown (first change is always allowed — usernameChangedAt null).
      if (me.usernameChangedAt) {
        const readyAt = me.usernameChangedAt.getTime() + USERNAME_COOLDOWN_MS;
        if (readyAt > Date.now()) {
          const days = Math.ceil((readyAt - Date.now()) / (24 * 60 * 60 * 1000));
          throw new ApiError(
            429,
            `You can change your username again in ${days} day${days === 1 ? '' : 's'}`
          );
        }
      }
      const taken = await User.findOne({ username: next, _id: { $ne: me._id } });
      if (taken) throw new ApiError(409, 'That username is already taken');

      me.username = next;
      me.usernameChangedAt = new Date();
    }
  }

  if (displayName !== undefined) me.displayName = displayName;
  if (bio !== undefined) me.bio = bio;
  if (showOnlineStatus !== undefined) {
    me.showOnlineStatus = Boolean(showOnlineStatus);
  }
  if (showLastSeen !== undefined) {
    me.showLastSeen = Boolean(showLastSeen);
  }
  if (receiveCalls !== undefined) {
    me.receiveCalls = Boolean(receiveCalls);
  }
  await me.save();
  return res
    .status(200)
    .json(new ApiResponse(200, { user: me.toSafeObject() }, 'Profile updated'));
});

// GET /api/v1/users/search?q=username
export const searchUsers = asyncHandler(async (req, res) => {
  const q = (req.query.q || '').trim().toLowerCase();
  if (!q) throw new ApiError(400, 'Search query is required');

  const found = await User.find({
    username: { $regex: q, $options: 'i' },
    _id: { $ne: req.user._id }, // never return yourself
  })
    .limit(20)
    .select('displayName username avatar bio isOnline showOnlineStatus');

  // Respect each result's online-status privacy (they're not the viewer).
  const users = found.map((u) => {
    const obj = u.toObject();
    if (obj.showOnlineStatus === false) obj.isOnline = false;
    delete obj.showOnlineStatus;
    return obj;
  });

  return res.status(200).json(new ApiResponse(200, { users }));
});

// GET /api/v1/users/:userId — public profile + relationship to the viewer.
// The relationship tells the client which action to show:
//   isContact   → "Message" (opens DM at roomId)
//   incoming    → "Accept" (incomingRequestId is pending, sent to me)
//   outgoing    → "Request sent" (I already sent one, still pending)
//   otherwise   → "Send request"
export const getPublicProfile = asyncHandler(async (req, res) => {
  const { userId } = req.params;
  const found = await User.findById(userId).select(
    'displayName username avatar bio isOnline lastSeenAt showOnlineStatus showLastSeen'
  );
  if (!found) throw new ApiError(404, 'User not found');

  const me = req.user._id;
  const isSelf = String(userId) === String(me);

  // Mask presence per the viewed user's privacy prefs (self is exempt).
  const user = found.toObject();
  if (!isSelf) {
    if (user.showOnlineStatus === false) user.isOnline = false;
    if (user.showLastSeen === false) user.lastSeenAt = null;
  }
  delete user.showOnlineStatus;
  delete user.showLastSeen;

  let isContact = false;
  let roomId = null;
  let incomingRequestId = null;
  let outgoingPending = false;

  if (!isSelf) {
    // Are we already contacts? If so, find our shared permanent room.
    isContact = req.user.contacts.some((c) => String(c) === String(userId));
    if (isContact) {
      const room = await Room.findOne({
        type: 'permanent',
        participants: { $all: [me, userId] },
      }).select('_id');
      roomId = room?._id ?? null;
    }

    // Any pending request between us (either direction).
    const [incoming, outgoing] = await Promise.all([
      ChatRequest.findOne({ from: userId, to: me, status: 'pending' }).select('_id'),
      ChatRequest.findOne({ from: me, to: userId, status: 'pending' }).select('_id'),
    ]);
    incomingRequestId = incoming?._id ?? null;
    outgoingPending = Boolean(outgoing);
  }

  // Our own mute state for this user (independent messages/calls timestamps).
  const muteEntry = req.user.mutedUsers?.find(
    (m) => String(m.userId) === String(userId)
  );

  return res.status(200).json(
    new ApiResponse(200, {
      user,
      relationship: {
        isSelf,
        isContact,
        roomId,
        incomingRequestId,
        outgoingPending,
        messagesMutedUntil: muteEntry?.messagesUntil ?? null,
        callsMutedUntil: muteEntry?.callsUntil ?? null,
      },
    })
  );
});

// PUT /api/v1/users/:userId/mute — set/clear this user's per-scope mute.
// Body: { messagesUntil?, callsUntil? } where each value is an epoch-ms number
// (future = muted until then; a far-future value = "until turned off"), or null
// to clear that scope. Omitted scopes are left unchanged. Returns the caller's
// updated safe profile (so the client can refresh its mute list).
export const setMute = asyncHandler(async (req, res) => {
  const { userId } = req.params;
  if (!mongoose.isValidObjectId(userId)) {
    throw new ApiError(400, 'Invalid user id');
  }
  if (String(userId) === String(req.user._id)) {
    throw new ApiError(400, 'You cannot mute yourself');
  }
  const target = await User.exists({ _id: userId });
  if (!target) throw new ApiError(404, 'User not found');

  const body = req.body || {};
  const hasMessages = Object.prototype.hasOwnProperty.call(body, 'messagesUntil');
  const hasCalls = Object.prototype.hasOwnProperty.call(body, 'callsUntil');
  if (!hasMessages && !hasCalls) {
    throw new ApiError(400, 'Provide messagesUntil and/or callsUntil');
  }
  const toDate = (v) =>
    v === null || v === undefined || !Number.isFinite(Number(v))
      ? null
      : new Date(Number(v));

  const list = (req.user.mutedUsers || []).map((m) => ({
    userId: m.userId,
    messagesUntil: m.messagesUntil,
    callsUntil: m.callsUntil,
  }));
  const existing = list.find((m) => String(m.userId) === String(userId));
  // Resolve the final value for each scope: the incoming one when provided,
  // otherwise whatever was already set.
  const nextMessages = hasMessages
    ? toDate(body.messagesUntil)
    : existing?.messagesUntil ?? null;
  const nextCalls = hasCalls
    ? toDate(body.callsUntil)
    : existing?.callsUntil ?? null;

  let nextList;
  if (!nextMessages && !nextCalls) {
    // Nothing muted → drop any existing entry to keep the array tidy.
    nextList = list.filter((m) => String(m.userId) !== String(userId));
  } else {
    const updatedEntry = { userId, messagesUntil: nextMessages, callsUntil: nextCalls };
    nextList = existing
      ? list.map((m) => (String(m.userId) === String(userId) ? updatedEntry : m))
      : [...list, updatedEntry];
  }

  // Atomic array replace — avoids full-document validation (verifyJWT strips
  // passwordHash, which the pre('validate') hook would otherwise reject).
  const updated = await User.findByIdAndUpdate(
    req.user._id,
    { mutedUsers: nextList },
    { new: true, runValidators: false }
  );
  return res
    .status(200)
    .json(new ApiResponse(200, { user: updated.toSafeObject() }));
});

// DELETE /api/v1/users/me  — permanently delete the account (full hard delete).
// Password-confirmed. Cascades: the user's permanent DM rooms + their messages
// (and encrypted file blobs), removes the user from everyone's contacts, drops
// any wrapped keys the other participants held for the deleted rooms, deletes
// chat requests in either direction, then deletes the user (fcmTokens go with
// it). Ephemeral rooms self-expire, so they're left alone.
export const deleteAccount = asyncHandler(async (req, res) => {
  const { password } = req.body;
  if (!password) throw new ApiError(400, 'password is required');

  // verifyJWT strips passwordHash — re-fetch the full doc to verify.
  const user = await User.findById(req.user._id);
  if (!user) throw new ApiError(404, 'User not found');
  const ok = await user.isPasswordCorrect(password);
  if (!ok) throw new ApiError(400, 'Password is incorrect');

  const userId = user._id;

  // 1. Permanent DM rooms this user belongs to.
  const rooms = await Room.find({
    type: 'permanent',
    participants: userId,
  }).select('_id');
  const roomIds = rooms.map((r) => r._id);

  if (roomIds.length) {
    // 2. Purge encrypted file blobs, then the message documents.
    const fileMsgs = await Message.find({
      roomId: { $in: roomIds },
      blobName: { $exists: true, $ne: null },
    }).select('blobName');
    const blobNames = fileMsgs.map((m) => m.blobName).filter(Boolean);
    if (blobNames.length) {
      try {
        await deleteBlobsByRoom(blobNames);
      } catch (err) {
        console.error('deleteAccount: R2 blob cleanup failed:', err.message);
      }
    }
    await Message.deleteMany({ roomId: { $in: roomIds } });

    // 3. Drop the OTHER participants' wrapped keys for these now-gone rooms.
    await User.updateMany(
      {},
      { $pull: { roomKeys: { roomId: { $in: roomIds } } } }
    );

    // 4. Delete the rooms themselves.
    await Room.deleteMany({ _id: { $in: roomIds } });
  }

  // 5. Remove this user from everyone else's contacts.
  await User.updateMany({ contacts: userId }, { $pull: { contacts: userId } });

  // 6. Delete chat requests in either direction.
  await ChatRequest.deleteMany({ $or: [{ from: userId }, { to: userId }] });

  // 7. Finally, delete the account (fcmTokens, roomKeys, etc. go with it).
  await User.deleteOne({ _id: userId });

  // Clear auth cookies for browser clients (native clients drop their own).
  res.clearCookie('accessToken');
  res.clearCookie('refreshToken');

  return res
    .status(200)
    .json(new ApiResponse(200, {}, 'Account deleted'));
});

// ---- Contacts -----------------------------------------------------------

// GET /api/v1/users/contacts
export const getContacts = asyncHandler(async (req, res) => {
  const me = await User.findById(req.user._id).populate(
    'contacts',
    'displayName username avatar bio isOnline lastSeenAt'
  );
  return res.status(200).json(new ApiResponse(200, { contacts: me.contacts }));
});

// POST /api/v1/users/:userId/contact
export const addContact = asyncHandler(async (req, res) => {
  const { userId } = req.params;
  if (userId === String(req.user._id)) {
    throw new ApiError(400, "You can't add yourself as a contact");
  }
  const target = await User.findById(userId);
  if (!target) throw new ApiError(404, 'User not found');

  // $addToSet keeps the array unique.
  await User.findByIdAndUpdate(req.user._id, {
    $addToSet: { contacts: userId },
  });
  return res.status(200).json(new ApiResponse(200, {}, 'Contact added'));
});

// DELETE /api/v1/users/:userId/contact
export const removeContact = asyncHandler(async (req, res) => {
  await User.findByIdAndUpdate(req.user._id, {
    $pull: { contacts: req.params.userId },
  });
  return res.status(200).json(new ApiResponse(200, {}, 'Contact removed'));
});

// ---- Chat requests ------------------------------------------------------

// POST /api/v1/requests  { toUserId }
export const sendChatRequest = asyncHandler(async (req, res) => {
  const { toUserId } = req.body;
  if (!toUserId) throw new ApiError(400, 'toUserId is required');
  if (toUserId === String(req.user._id)) {
    throw new ApiError(400, "You can't send a request to yourself");
  }

  const target = await User.findById(toUserId);
  if (!target) throw new ApiError(404, 'User not found');

  // Reject duplicates in either direction that are still pending/accepted.
  const existing = await ChatRequest.findOne({
    $or: [
      { from: req.user._id, to: toUserId },
      { from: toUserId, to: req.user._id },
    ],
    status: { $in: ['pending', 'accepted'] },
  });
  if (existing) {
    throw new ApiError(409, 'A request already exists between you two');
  }

  const request = await ChatRequest.create({
    from: req.user._id,
    to: toUserId,
    status: 'pending',
  });

  // Realtime + push notification to the recipient (content-free).
  try {
    getIO()
      .to(`user:${toUserId}`)
      .emit(SOCKET_EVENTS.CHAT_REQUEST, {
        requestId: request._id,
        from: {
          userId: req.user._id,
          displayName: req.user.displayName,
          username: req.user.username,
          avatar: req.user.avatar,
        },
      });
  } catch {
    // Socket layer may not be up in some contexts — non-fatal.
  }
  for (const token of target.fcmTokens) {
    sendChatRequestNotification(token, req.user.displayName);
  }

  return res
    .status(201)
    .json(new ApiResponse(201, { request }, 'Chat request sent'));
});

// GET /api/v1/requests — incoming + outgoing
export const getChatRequests = asyncHandler(async (req, res) => {
  const [incoming, outgoing] = await Promise.all([
    ChatRequest.find({ to: req.user._id, status: 'pending' }).populate(
      'from',
      'displayName username avatar'
    ),
    ChatRequest.find({ from: req.user._id, status: 'pending' }).populate(
      'to',
      'displayName username avatar'
    ),
  ]);
  return res.status(200).json(new ApiResponse(200, { incoming, outgoing }));
});

// PATCH /api/v1/requests/:requestId/accept
// Creates the permanent DM room. No key material is exchanged or stored: both
// participants derive the room key locally from the room id via PBKDF2 (same
// model as ephemeral rooms). The server therefore holds no keys at all.
export const acceptChatRequest = asyncHandler(async (req, res) => {
  const request = await ChatRequest.findById(req.params.requestId);
  if (!request) throw new ApiError(404, 'Request not found');
  if (String(request.to) !== String(req.user._id)) {
    throw new ApiError(403, 'You can only accept requests sent to you');
  }
  if (request.status !== 'pending') {
    throw new ApiError(409, `Request already ${request.status}`);
  }

  // Create the permanent room shared by both participants.
  const room = await Room.create({
    type: 'permanent',
    name: 'Direct Message',
    createdBy: String(req.user._id),
    participants: [request.from, request.to],
  });

  // Make them contacts both ways.
  await User.findByIdAndUpdate(req.user._id, {
    $addToSet: { contacts: request.from },
  });
  await User.findByIdAndUpdate(request.from, {
    $addToSet: { contacts: request.to },
  });

  request.status = 'accepted';
  await request.save();

  // Tell the requester the room now exists so their chats list can refresh.
  // They independently derive the same key from the room id — nothing secret
  // is sent here.
  try {
    getIO()
      .to(`user:${request.from}`)
      .emit(SOCKET_EVENTS.REQUEST_ACCEPTED, {
        roomId: room._id,
        requestId: request._id,
        acceptedBy: {
          userId: req.user._id,
          displayName: req.user.displayName,
          avatar: req.user.avatar,
        },
      });
  } catch {
    // Non-fatal if socket layer unavailable.
  }

  return res
    .status(200)
    .json(new ApiResponse(200, { room }, 'Chat request accepted'));
});

// PATCH /api/v1/requests/:requestId/reject
export const rejectChatRequest = asyncHandler(async (req, res) => {
  const request = await ChatRequest.findById(req.params.requestId);
  if (!request) throw new ApiError(404, 'Request not found');
  if (String(request.to) !== String(req.user._id)) {
    throw new ApiError(403, 'You can only reject requests sent to you');
  }
  request.status = 'rejected';
  await request.save();
  return res.status(200).json(new ApiResponse(200, {}, 'Chat request rejected'));
});
