// Redis service — all volatile, per-session state lives here (presence, aliases,
// colours, typing indicators, socket↔user mapping, knocks, rate limiting).
//
// A single ioredis client is shared for app logic; the Socket.io Redis adapter
// creates its own duplicated pub/sub pair (see socket/index.js).
//
// Every key is namespaced under `cypherfy:` (REDIS_PREFIX).

import Redis from 'ioredis';
import { REDIS_PREFIX, FCM_OFFLINE_THRESHOLD_SECONDS } from '../constants.js';

let redis = null;

/**
 * Connect (lazily create) the shared Redis client. Called once at startup.
 * @returns {Promise<Redis>}
 */
export const connectRedis = async () => {
  if (redis) return redis;

  redis = new Redis(process.env.REDIS_URL, {
    // Fail fast at boot rather than buffering commands forever.
    maxRetriesPerRequest: 3,
    lazyConnect: true,
  });

  redis.on('error', (err) => console.error('Redis error:', err.message));

  await redis.connect();
  console.log('Redis connected');
  return redis;
};

/** Return the live client, throwing if connectRedis() has not run. */
export const getRedis = () => {
  if (!redis) throw new Error('Redis not connected — call connectRedis() first');
  return redis;
};

// ---- Key builders -------------------------------------------------------
const roomUsersKey = (code) => `${REDIS_PREFIX}:room:${code}:users`;
const roomAliasesKey = (code) => `${REDIS_PREFIX}:room:${code}:aliases`;
const roomColorsKey = (code) => `${REDIS_PREFIX}:room:${code}:colors`;
const typingKey = (roomId, alias) => `${REDIS_PREFIX}:typing:${roomId}:${alias}`;
const socketUserKey = (socketId) => `${REDIS_PREFIX}:socket:${socketId}`;
const disconnectKey = (socketId) => `${REDIS_PREFIX}:disconnect:${socketId}`;
const knockKey = (code, socketId) => `${REDIS_PREFIX}:knock:${code}:${socketId}`;
// Sockets the host has admitted into a locked room (bypass the lock on join).
const admittedKey = (code) => `${REDIS_PREFIX}:room:${code}:admitted`;
const rateLimitKey = (ip) => `${REDIS_PREFIX}:ratelimit:${ip}`;
// Auth exponential-backoff (scope = 'ip' | 'account'). `count` accrues attempts
// within the decay window; `block` exists only while a backoff penalty is active.
const authCountKey = (scope, id) => `${REDIS_PREFIX}:authbackoff:${scope}:${id}:count`;
const authBlockKey = (scope, id) => `${REDIS_PREFIX}:authbackoff:${scope}:${id}:block`;
// Call sessions (voice/video). A call is a mesh of member sockets tied to a
// room channel (`perm:<roomId>` for DMs, the room code for ephemeral groups).
const callMembersKey = (callId) => `${REDIS_PREFIX}:call:${callId}:members`;
const callMetaKey = (callId) => `${REDIS_PREFIX}:call:${callId}:meta`;
const channelCallKey = (channel) => `${REDIS_PREFIX}:callchan:${channel}`;
const userCallKey = (userId) => `${REDIS_PREFIX}:usercall:${userId}`;

// ---- Room presence ------------------------------------------------------

export const addUserToRoom = (roomCode, socketId) =>
  getRedis().sadd(roomUsersKey(roomCode), socketId);

export const removeUserFromRoom = (roomCode, socketId) =>
  getRedis().srem(roomUsersKey(roomCode), socketId);

/** @returns {Promise<string[]>} socket IDs currently in the room */
export const getRoomUsers = (roomCode) =>
  getRedis().smembers(roomUsersKey(roomCode));

// ---- Alias map ----------------------------------------------------------

export const setAlias = (roomCode, socketId, alias) =>
  getRedis().hset(roomAliasesKey(roomCode), socketId, alias);

export const getAlias = (roomCode, socketId) =>
  getRedis().hget(roomAliasesKey(roomCode), socketId);

/** @returns {Promise<Record<string,string>>} socketId → alias */
export const getAllAliases = (roomCode) =>
  getRedis().hgetall(roomAliasesKey(roomCode));

export const removeAlias = (roomCode, socketId) =>
  getRedis().hdel(roomAliasesKey(roomCode), socketId);

// ---- Colour map ---------------------------------------------------------

export const setColor = (roomCode, socketId, color) =>
  getRedis().hset(roomColorsKey(roomCode), socketId, color);

export const getColor = (roomCode, socketId) =>
  getRedis().hget(roomColorsKey(roomCode), socketId);

// ---- Typing indicators (auto-expire after 3s) ---------------------------

export const setTyping = (roomId, alias) =>
  getRedis().set(typingKey(roomId, alias), '1', 'EX', 3);

export const clearTyping = (roomId, alias) =>
  getRedis().del(typingKey(roomId, alias));

/**
 * List aliases currently typing in a room. Scans the typing keyspace for the
 * room and extracts the alias segment from each surviving key.
 * @returns {Promise<string[]>}
 */
export const getTypingUsers = async (roomId) => {
  const pattern = `${REDIS_PREFIX}:typing:${roomId}:*`;
  const keys = await scanKeys(pattern);
  const prefixLen = `${REDIS_PREFIX}:typing:${roomId}:`.length;
  return keys.map((k) => k.slice(prefixLen));
};

// ---- Socket ↔ user mapping (account users) ------------------------------

export const setSocketUser = (socketId, userId) =>
  getRedis().set(socketUserKey(socketId), String(userId), 'EX', 86400);

export const getSocketUser = (socketId) =>
  getRedis().get(socketUserKey(socketId));

export const removeSocketUser = (socketId) =>
  getRedis().del(socketUserKey(socketId));

// ---- Disconnect timing (drives FCM decisions) ---------------------------

export const setDisconnectTime = (socketId) =>
  getRedis().set(disconnectKey(socketId), Date.now().toString(), 'EX', 300);

/**
 * Should we send an FCM push to the owner of this socket? True only if they've
 * been disconnected longer than the threshold (so we don't buzz active users).
 * @returns {Promise<boolean>}
 */
export const shouldSendFcm = async (socketId) => {
  const ts = await getRedis().get(disconnectKey(socketId));
  if (!ts) return true; // no record → treat as offline, safe to notify
  const elapsedSeconds = (Date.now() - Number(ts)) / 1000;
  return elapsedSeconds > FCM_OFFLINE_THRESHOLD_SECONDS;
};

// ---- Knock requests -----------------------------------------------------

export const setKnock = (code, socketId, alias) =>
  getRedis().set(knockKey(code, socketId), alias, 'EX', 300);

export const getKnock = (code, socketId) =>
  getRedis().get(knockKey(code, socketId));

export const deleteKnock = (code, socketId) =>
  getRedis().del(knockKey(code, socketId));

/**
 * List every knock still pending for a room. Used to deliver knocks that
 * arrived before the host had joined (so the host isn't left unaware).
 * @returns {Promise<Array<{ socketId: string, alias: string }>>}
 */
export const getPendingKnocks = async (code) => {
  const prefix = `${REDIS_PREFIX}:knock:${code}:`;
  const keys = await scanKeys(`${prefix}*`);
  const out = [];
  for (const key of keys) {
    // eslint-disable-next-line no-await-in-loop
    const alias = await getRedis().get(key);
    if (alias) out.push({ socketId: key.slice(prefix.length), alias });
  }
  return out;
};

// ---- Admission (locked rooms) -------------------------------------------

/** Mark a socket as admitted to a locked room so join_room lets it through. */
export const addAdmitted = (code, socketId) =>
  getRedis().sadd(admittedKey(code), socketId);

/** Whether a socket has been admitted into a locked room. */
export const isAdmitted = async (code, socketId) =>
  (await getRedis().sismember(admittedKey(code), socketId)) === 1;

// ---- Rate limiting (room-code brute force prevention) -------------------

/**
 * Increment the per-IP counter, setting a 60s expiry on first hit.
 * @returns {Promise<number>} the new count within the window
 */
export const incrementRateLimit = async (ip) => {
  const key = rateLimitKey(ip);
  const count = await getRedis().incr(key);
  if (count === 1) await getRedis().expire(key, 60);
  return count;
};

// ---- Auth exponential backoff (per-IP / per-account) --------------------
//
// Records one auth attempt for an identity and applies exponential backoff once
// the free-attempt budget for the decay window is exhausted. This is a THROTTLE,
// not a lockout: the penalty is a bounded, growing delay (BASE, BASE*2 … up to
// MAX), every identity recovers on its own, and the counter resets after DECAY
// of inactivity. Callers combine an 'ip' and an 'account' check and honour the
// larger retry-after.
//
// @param {'ip'|'account'} scope
// @param {string} id                 client IP or lowercased email
// @param {{freeAttempts:number, backoffBaseMs:number, backoffMaxMs:number, decayMs:number}} opts
// @returns {Promise<{limited:boolean, retryAfterSec:number}>}
export const registerAuthAttempt = async (
  scope,
  id,
  { freeAttempts, backoffBaseMs, backoffMaxMs, decayMs }
) => {
  const redis = getRedis();
  const blockKey = authBlockKey(scope, id);

  // Currently serving a penalty → reject with the remaining time; don't let
  // hammering during a block inflate the counter further.
  const blockTtlMs = await redis.pttl(blockKey);
  if (blockTtlMs > 0) {
    return { limited: true, retryAfterSec: Math.ceil(blockTtlMs / 1000) };
  }

  const countKey = authCountKey(scope, id);
  const count = await redis.incr(countKey);
  if (count === 1) await redis.pexpire(countKey, decayMs);

  if (count <= freeAttempts) {
    return { limited: false, retryAfterSec: 0 };
  }

  // Budget spent — apply an exponentially growing block.
  const violations = count - freeAttempts;
  const delayMs = Math.min(backoffBaseMs * 2 ** (violations - 1), backoffMaxMs);
  await redis.set(blockKey, String(violations), 'PX', delayMs);
  // Keep the counter alive at least as long as the block so repeat offenders
  // keep climbing the backoff curve rather than resetting mid-penalty.
  await redis.pexpire(countKey, Math.max(decayMs, delayMs));
  return { limited: true, retryAfterSec: Math.ceil(delayMs / 1000) };
};

/**
 * Clear an identity's backoff state — call after a *successful* auth so a
 * legitimate user is never penalised for a few earlier failures.
 * @param {Array<[('ip'|'account'), string]>} identities
 */
export const resetAuthAttempts = async (identities) => {
  const redis = getRedis();
  const keys = identities.flatMap(([scope, id]) => [
    authCountKey(scope, id),
    authBlockKey(scope, id),
  ]);
  if (keys.length) await redis.del(...keys);
};

// ---- Call sessions ------------------------------------------------------
//
// Members are stored socketId → JSON({userId,name}). A per-channel pointer lets
// a late joiner discover an in-progress group call; a per-user marker powers the
// DM "busy" check. All keys carry a generous TTL so a crash can never leak state.

const CALL_TTL = 4 * 3600; // 4h safety net

/** Create the call's metadata record. */
export const createCall = async (callId, { channel, callType, callerUserId }) => {
  await getRedis().hset(callMetaKey(callId), {
    channel,
    callType: callType || 'audio',
    callerUserId: String(callerUserId),
    startedAt: String(Date.now()), // for the "call running for MM:SS" label
  });
  await getRedis().expire(callMetaKey(callId), CALL_TTL);
};

/** @returns {Promise<{channel:string,callType:string,callerUserId:string,startedAt:string}|null>} */
export const getCallMeta = async (callId) => {
  const m = await getRedis().hgetall(callMetaKey(callId));
  return m && m.channel ? m : null;
};

/** Add a socket to the call. `member` = { userId, name }. */
export const addCallMember = async (callId, socketId, member) => {
  await getRedis().hset(callMembersKey(callId), socketId, JSON.stringify(member));
  await getRedis().expire(callMembersKey(callId), CALL_TTL);
};

export const removeCallMember = (callId, socketId) =>
  getRedis().hdel(callMembersKey(callId), socketId);

/** @returns {Promise<Record<string,{userId:string,name:string}>>} socketId → member */
export const getCallMembers = async (callId) => {
  const raw = await getRedis().hgetall(callMembersKey(callId));
  const out = {};
  for (const [sid, val] of Object.entries(raw)) {
    try {
      out[sid] = JSON.parse(val);
    } catch {
      out[sid] = {};
    }
  }
  return out;
};

export const setChannelCall = (channel, callId) =>
  getRedis().set(channelCallKey(channel), callId, 'EX', CALL_TTL);

export const getChannelCall = (channel) => getRedis().get(channelCallKey(channel));

export const delChannelCall = (channel) => getRedis().del(channelCallKey(channel));

export const setUserInCall = (userId, callId) =>
  getRedis().set(userCallKey(userId), String(callId), 'EX', CALL_TTL);

export const getUserCall = (userId) => getRedis().get(userCallKey(userId));

export const clearUserInCall = (userId) => getRedis().del(userCallKey(userId));

/** Delete a finished call's records (members + meta). */
export const deleteCall = (callId) =>
  getRedis().del(callMembersKey(callId), callMetaKey(callId));

/**
 * Tear down a finished call session: clear every member's "in a call" marker
 * (so a stale marker can't wrongly gate a future call), then delete the channel
 * pointer and the call records. `members` may be passed to skip a re-read.
 */
export const reapCall = async (callId, channel, members) => {
  const roster = members || (await getCallMembers(callId));
  for (const info of Object.values(roster)) {
    if (info.userId) await clearUserInCall(info.userId);
  }
  await delChannelCall(channel);
  await deleteCall(callId);
};

// ---- Room cleanup -------------------------------------------------------

/** Delete every Redis key associated with a room (on end/expire). */
export const cleanupRoom = async (roomCode) => {
  const pattern = `${REDIS_PREFIX}:room:${roomCode}:*`;
  const keys = await scanKeys(pattern);
  if (keys.length) await getRedis().del(...keys);
};

// ---- Internal: non-blocking SCAN helper ---------------------------------

/** Collect all keys matching a pattern using SCAN (never KEYS in prod). */
const scanKeys = async (pattern) => {
  const client = getRedis();
  const found = [];
  let cursor = '0';
  do {
    const [next, batch] = await client.scan(
      cursor,
      'MATCH',
      pattern,
      'COUNT',
      100
    );
    cursor = next;
    found.push(...batch);
  } while (cursor !== '0');
  return found;
};
