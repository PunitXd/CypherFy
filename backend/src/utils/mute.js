// Per-user mute helpers, shared by the message + call handlers.
//
// A user document carries `mutedUsers: [{ userId, messagesUntil, callsUntil }]`.
// A scope is muted when its `*Until` is a Date in the future (a far-future date
// represents "until I turn it back on").

/**
 * Is `otherUserId` currently muted for `scope` by `user`?
 * @param {object} user  a User doc/lean object with `mutedUsers`
 * @param {string} otherUserId
 * @param {'messagesUntil'|'callsUntil'} scope
 */
export const isMuted = (user, otherUserId, scope) => {
  const entry = user?.mutedUsers?.find(
    (m) => String(m.userId) === String(otherUserId)
  );
  const until = entry?.[scope];
  return Boolean(until && new Date(until).getTime() > Date.now());
};
