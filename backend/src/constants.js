// Application-wide constants for CypherFy.
// Keeping these in one place makes tuning limits and copy trivial.

export const DB_NAME = 'cypherfy';

// Room configuration ------------------------------------------------------
export const ROOM = {
  CODE_LENGTH: 6,
  MAX_USERS_OPTIONS: [2, 3, 4, 5, 6, 8, 10],
  DEFAULT_MAX_USERS: 2,
  // Named TTL presets (seconds) exposed to the client.
  TTL_OPTIONS: {
    '1h': 3600,
    '6h': 21600,
    '24h': 86400,
    '7d': 604800,
  },
  DEFAULT_TTL: 3600,
  // How long before auto-delete we warn the room.
  EXPIRY_WARNING_SECONDS: 60,
};

// Password reset (OTP + emailed link) ------------------------------------
export const PASSWORD_RESET = {
  OTP_LENGTH: 6,
  TTL_MS: 15 * 60 * 1000, // window for OTP / link / ticket
  MAX_OTP_ATTEMPTS: 5, // wrong-code tries before the attempt is invalidated
};

export const EMAIL_VERIFICATION = {
  OTP_LENGTH: 6,
  TTL_MS: 15 * 60 * 1000, // window to enter the emailed code
  MAX_OTP_ATTEMPTS: 5, // wrong-code tries before the code is invalidated
};

// File / upload limits ----------------------------------------------------
export const FILE = {
  MAX_SIZE_MB: 25,
  MAX_SIZE_BYTES: 25 * 1024 * 1024,
  AVATAR_MAX_MB: 5,
  TEMP_DIR: './public/temp',
};

// Anonymous alias generation for ephemeral rooms --------------------------
export const ALIAS = {
  ADJECTIVES: [
    'Red', 'Blue', 'Swift', 'Dark', 'Bright', 'Silent', 'Bold', 'Calm',
    'Sharp', 'Keen', 'Wild', 'Frost', 'Storm', 'Solar', 'Lunar', 'Crisp',
    'Jade', 'Amber', 'Coral', 'Teal', 'Onyx', 'Sage', 'Azure', 'Ember',
    'Cobalt', 'Silver', 'Golden', 'Misty', 'Neon', 'Polar',
  ],
  ANIMALS: [
    'Fox', 'Owl', 'Wolf', 'Bear', 'Hawk', 'Lynx', 'Crow', 'Deer', 'Hare',
    'Mink', 'Seal', 'Ibis', 'Wren', 'Kite', 'Dove', 'Puma', 'Boar', 'Newt',
    'Vole', 'Mole', 'Finch', 'Crane', 'Raven', 'Otter', 'Bison', 'Moose',
    'Viper', 'Gecko', 'Stoat',
  ],
  COLORS: [
    '#7F77DD', '#1D9E75', '#D85A30', '#BA7517', '#D4537E',
    '#378ADD', '#639922', '#E24B4A', '#54C5F8', '#F48120',
  ],
};

// Socket.io event names — shared vocabulary between client and server.
export const SOCKET_EVENTS = {
  // Client → Server
  CREATE_ROOM: 'create_room',
  JOIN_ROOM: 'join_room',
  END_ROOM: 'end_room',
  JOIN_PERMANENT: 'join_permanent',
  LEAVE_ROOM: 'leave_room',
  SEND_MESSAGE: 'send_message',
  SEND_FILE: 'send_file',
  ADD_REACTION: 'add_reaction',
  DELETE_MESSAGE: 'delete_message',
  KNOCK: 'knock',
  ADMIT_USER: 'admit_user',
  REJECT_USER: 'reject_user',
  TYPING_START: 'typing_start',
  TYPING_STOP: 'typing_stop',
  MESSAGE_SEEN: 'message_seen', // recipient reports delivered/read up to a point

  // --- Calls: session setup (client → server) ---
  CALL_START: 'call:start', // begin/join a call in a DM or ephemeral room
  CALL_ACCEPT: 'call:accept', // answer a ringing call
  CALL_REJECT: 'call:reject', // decline a ringing call
  CALL_CANCEL: 'call:cancel', // caller aborts before it's answered
  CALL_LEAVE: 'call:leave', // hang up / leave an active call
  CALL_GROUP_STATE: 'call:group_state', // ask if a group call is ongoing in a room

  // --- Calls: mesh signalling relays (client ↔ server, carry callId+target) ---
  WEBRTC_OFFER: 'webrtc_offer',
  WEBRTC_ANSWER: 'webrtc_answer',
  ICE_CANDIDATE: 'ice_candidate',

  SAVE_FCM_TOKEN: 'save_fcm_token',
  REMOVE_FCM_TOKEN: 'remove_fcm_token',
  UPDATE_ONLINE: 'update_online',

  // Server → Client
  ROOM_CREATED: 'room_created',
  ROOM_JOINED: 'room_joined',
  ROOM_EXPIRING: 'room_expiring',
  ROOM_EXPIRED: 'room_expired',
  ROOM_ENDED: 'room_ended',
  NEW_MESSAGE: 'new_message',
  MESSAGE_DELETED: 'message_deleted',
  REACTION_UPDATED: 'reaction_updated',
  RECEIPT_UPDATE: 'receipt_update', // someone delivered/read messages up to a point
  USER_JOINED: 'user_joined',
  USER_LEFT: 'user_left',
  TYPING_UPDATE: 'typing_update',
  ONLINE_STATUS: 'online_status',
  KNOCK_REQUEST: 'knock_request',
  KNOCK_ADMITTED: 'knock_admitted',
  KNOCK_REJECTED: 'knock_rejected',

  // --- Calls: session lifecycle (server → client) ---
  CALL_INCOMING: 'call:incoming', // a call is ringing you
  CALL_STARTED: 'call:started', // ack to the caller (callId + iceServers)
  CALL_ACCEPTED: 'call:accepted', // ack to accepter (roster of existing peers)
  CALL_PEER_JOINED: 'call:peer_joined', // a new peer entered the call (mesh)
  CALL_PEER_LEFT: 'call:peer_left', // a peer left the call
  CALL_REJECTED: 'call:rejected', // callee declined (1:1 → ends the caller)
  CALL_PEER_DECLINED: 'call:peer_declined', // a group invitee declined (info only)
  CALL_CANCELLED: 'call:cancelled', // caller aborted before answer
  CALL_BUSY: 'call:busy', // callee is already in another call
  CALL_ENDED: 'call:ended', // the whole call session ended
  CALL_GROUP_ACTIVE: 'call:group_active', // a group call is ongoing in this room (banner)
  CALL_GROUP_ENDED: 'call:group_ended', // the group call in this room is over (hide banner)
  CHAT_REQUEST: 'chat_request',
  REQUEST_ACCEPTED: 'request_accepted',
  // Content-free ping to a permanent-room participant's personal channel
  // (user:<id>) so their home screen updates live even when not in the chat.
  DM_ACTIVITY: 'dm_activity',
  ERROR: 'error',
};

// Canonical error codes emitted on the socket `error` event.
export const ERROR_CODES = {
  ROOM_FULL: 'ROOM_FULL',
  INVALID_CODE: 'INVALID_CODE',
  WRONG_PASSPHRASE: 'WRONG_PASSPHRASE',
  UNAUTHORIZED: 'UNAUTHORIZED',
  ROOM_NOT_FOUND: 'ROOM_NOT_FOUND',
  NOT_HOST: 'NOT_HOST',
  REQUEST_EXISTS: 'REQUEST_EXISTS',
};

// Redis key prefix — every key lives under this namespace.
export const REDIS_PREFIX = 'cypherfy';

// Only fire an FCM push if the recipient has been offline this long (seconds).
export const FCM_OFFLINE_THRESHOLD_SECONDS = 30;

// Rate limiting -----------------------------------------------------------
// Every threshold below is env-configurable (see .env.example) — nothing is
// hardcoded. Defaults are tuned for production; development gets looser limits
// so testing isn't blocked. `RATE_LIMIT_ENABLED=false` turns off all HTTP rate
// limiting (handy for tests). NODE_ENV is already populated by dotenv at load.
const rlProd = process.env.NODE_ENV === 'production';
const envInt = (name, fallback) => {
  const n = Number(process.env[name]);
  return Number.isFinite(n) && process.env[name] !== '' ? n : fallback;
};
const envBool = (name, fallback) =>
  process.env[name] === undefined || process.env[name] === ''
    ? fallback
    : /^(1|true|yes|on)$/i.test(process.env[name]);

export const RATE_LIMIT = {
  // Master switch across every HTTP limiter.
  ENABLED: envBool('RATE_LIMIT_ENABLED', true),

  // Strict tier — auth routes (login/register/password-reset/OTP/refresh).
  // Enforced per-IP AND per-account (email) with EXPONENTIAL BACKOFF, not a
  // hard lockout: once the free-attempt budget in the decay window is spent,
  // each further attempt is delayed BASE, BASE*2, BASE*4 … up to MAX. Every
  // identity always recovers after a bounded wait, and counters fully reset
  // after DECAY_MS of inactivity (or immediately on a successful login).
  AUTH: {
    IP_FREE_ATTEMPTS: envInt('RATE_LIMIT_AUTH_IP_FREE', rlProd ? 30 : 300),
    ACCOUNT_FREE_ATTEMPTS: envInt('RATE_LIMIT_AUTH_ACCOUNT_FREE', rlProd ? 8 : 100),
    BACKOFF_BASE_MS: envInt('RATE_LIMIT_AUTH_BACKOFF_BASE_MS', 30 * 1000), // 30s
    BACKOFF_MAX_MS: envInt('RATE_LIMIT_AUTH_BACKOFF_MAX_MS', 60 * 60 * 1000), // 1h cap
    DECAY_MS: envInt('RATE_LIMIT_AUTH_DECAY_MS', 60 * 60 * 1000), // 1h memory window
  },

  // Moderate tier — public endpoints (guest room create/validate, presigned URLs).
  PUBLIC: {
    WINDOW_MS: envInt('RATE_LIMIT_PUBLIC_WINDOW_MS', 60 * 1000),
    MAX: envInt('RATE_LIMIT_PUBLIC_MAX', rlProd ? 30 : 300),
  },

  // Loose tier — authenticated user actions (users/requests/calls/permanent rooms).
  // Keyed per-account (user id), so one user can't be throttled by another.
  USER: {
    WINDOW_MS: envInt('RATE_LIMIT_USER_WINDOW_MS', 60 * 1000),
    MAX: envInt('RATE_LIMIT_USER_MAX', rlProd ? 120 : 1000),
  },

  // Global safety net across all of /api (very loose — catches runaway clients).
  GLOBAL: {
    WINDOW_MS: envInt('RATE_LIMIT_GLOBAL_WINDOW_MS', 60 * 1000),
    MAX: envInt('RATE_LIMIT_GLOBAL_MAX', rlProd ? 300 : 3000),
  },
};
