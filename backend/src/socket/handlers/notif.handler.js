// Notification / presence handler.
//
// Handles FCM token registration and online-status broadcasts for account
// users. Presence is shared only with the user's contacts.

import { User } from '../../models/user.model.js';
import { SOCKET_EVENTS } from '../../constants.js';
import { validatePayload } from '../../middlewares/validate.middleware.js';
import { socketSchemas } from '../../validators/socket.schemas.js';

export const registerNotifHandlers = (io, socket) => {
  // ---- save_fcm_token -------------------------------------------------
  socket.on(SOCKET_EVENTS.SAVE_FCM_TOKEN, async (rawPayload) => {
    const v = validatePayload(socketSchemas.saveFcmToken, rawPayload);
    if (!v.ok) return;
    try {
      const { token } = v.data;
      if (!socket.data.userId) return;
      // $addToSet avoids duplicate tokens across reconnects.
      await User.findByIdAndUpdate(socket.data.userId, {
        $addToSet: { fcmTokens: token },
      });
    } catch (err) {
      console.error('save_fcm_token error:', err.message);
    }
  });

  // ---- remove_fcm_token ----------------------------------------------
  // Fired when the user turns push notifications off, so this device stops
  // receiving them. $pull removes just this token; other devices are unaffected.
  socket.on(SOCKET_EVENTS.REMOVE_FCM_TOKEN, async (rawPayload) => {
    const v = validatePayload(socketSchemas.removeFcmToken, rawPayload);
    if (!v.ok) return;
    try {
      const { token } = v.data;
      if (!socket.data.userId) return;
      await User.findByIdAndUpdate(socket.data.userId, {
        $pull: { fcmTokens: token },
      });
    } catch (err) {
      console.error('remove_fcm_token error:', err.message);
    }
  });

  // ---- update_online --------------------------------------------------
  socket.on(SOCKET_EVENTS.UPDATE_ONLINE, async (rawPayload) => {
    const v = validatePayload(socketSchemas.updateOnline, rawPayload);
    if (!v.ok) return;
    try {
      if (!socket.data.userId) return;
      const isOnline = v.data.isOnline ?? true;

      const user = await User.findByIdAndUpdate(
        socket.data.userId,
        { isOnline, lastSeenAt: new Date() },
        { new: true }
      ).select('contacts displayName showOnlineStatus showLastSeen');
      if (!user) return;

      // Cache displayName on the socket so message/typing handlers can label
      // permanent-room events without re-querying.
      socket.data.displayName = user.displayName;

      // Notify contacts of the status change (masked per the user's privacy).
      broadcastPresence(io, user._id, user.contacts, isOnline, user);
    } catch (err) {
      console.error('update_online error:', err.message);
    }
  });

  // On connect, if authenticated, mark online and announce to contacts.
  if (socket.data.userId) {
    markOnline(io, socket.data.userId, true).catch(() => {});
  }

  // On disconnect, mark offline and announce.
  socket.on('disconnect', async () => {
    if (socket.data.userId) {
      await markOnline(io, socket.data.userId, false).catch(() => {});
    }
  });
};

// Flip a user's online flag and tell their contacts.
async function markOnline(io, userId, isOnline) {
  const user = await User.findByIdAndUpdate(
    userId,
    { isOnline, lastSeenAt: new Date() },
    { new: true }
  ).select('contacts showOnlineStatus showLastSeen');
  if (user) broadcastPresence(io, userId, user.contacts, isOnline, user);
}

// Emit online_status to each contact's private room, masked per the user's
// privacy prefs: online status off → always appear offline; last-seen off →
// send no timestamp.
function broadcastPresence(io, userId, contacts, isOnline, prefs = {}) {
  const showOnline = prefs.showOnlineStatus !== false;
  const showSeen = prefs.showLastSeen !== false;
  const evt = {
    userId,
    isOnline: showOnline ? isOnline : false,
    lastSeenAt: showSeen ? new Date() : null,
  };
  for (const contactId of contacts || []) {
    io.to(`user:${contactId}`).emit(SOCKET_EVENTS.ONLINE_STATUS, evt);
  }
}
