// User model — account holders (permanent DM users).
//
// Security notes:
//  - passwordHash is a bcrypt hash, never the raw password.
//  - roomKeys[].encryptedKey is a permanent room key that has been WRAPPED with
//    a key derived from the user's password (client-side). The server stores
//    only ciphertext + IV and can never unwrap it.

import mongoose, { Schema } from 'mongoose';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';

const userSchema = new Schema(
  {
    email: {
      type: String,
      unique: true,
      required: true,
      lowercase: true,
      trim: true,
    },
    // Optional: social accounts have no password. The schema validator below
    // requires either a passwordHash or a firebaseUid, so no account is ever
    // credential-less.
    passwordHash: {
      type: String,
    },
    // Firebase Auth uid — the identity key for social sign-ins routed through
    // Firebase (Google, Apple, …). sparse+unique.
    firebaseUid: {
      type: String,
      unique: true,
      sparse: true,
      default: undefined,
    },
    displayName: {
      type: String,
      required: true,
      trim: true,
    },
    username: {
      type: String,
      unique: true, // unique already creates the lookup index
      required: true,
      lowercase: true,
      trim: true,
    },
    // When the username was last changed. Enforces the 30-day change cooldown.
    // null = never changed (e.g. Google users keep their auto-generated handle),
    // so the first change is always allowed.
    usernameChangedAt: {
      type: Date,
      default: null,
    },
    avatar: {
      type: String, // R2 URL
      default: null,
    },
    bio: {
      type: String,
      default: '',
    },

    // Accepted contacts / friends.
    contacts: [
      {
        type: Schema.Types.ObjectId,
        ref: 'User',
      },
    ],

    // Password-wrapped room keys for permanent rooms. The server never sees the
    // raw key — only the ciphertext and the IV used to encrypt it.
    roomKeys: [
      {
        roomId: { type: Schema.Types.ObjectId, ref: 'Room' },
        encryptedKey: { type: String }, // AES-GCM(roomKey, wrappingKey)
        keyIv: { type: String }, // IV used for the wrap
      },
    ],

    // FCM device tokens (a user may be logged in on several devices).
    fcmTokens: {
      type: [String],
      default: [],
    },
    isOnline: {
      type: Boolean,
      default: false,
    },
    lastSeenAt: {
      type: Date,
      default: Date.now,
    },

    // ---- Privacy preferences ----
    // When off, the corresponding presence field is masked from OTHER users
    // (self always sees the real value). Enforced server-side in
    // getPublicProfile, search, permanent-room populate, and presence broadcasts.
    showOnlineStatus: {
      type: Boolean,
      default: true,
    },
    showLastSeen: {
      type: Boolean,
      default: true,
    },

    // ---- Call preferences ----
    // When off, this user is a full "do not disturb" for calls: no live ring and
    // no push. Enforced server-side in the call:start DM branch (webrtc.handler).
    receiveCalls: {
      type: Boolean,
      default: true,
    },

    // ---- Per-user mute ----
    // Independently silence a specific user's message notifications and/or their
    // incoming calls, each until a timestamp. A far-future date means "until I
    // turn it back on". A null/past date means not muted for that scope. Enforced
    // server-side before FCM/ring (message.handler, webrtc.handler) via
    // utils/mute.js. Client mirrors these to show badges + suppress in-app.
    mutedUsers: [
      {
        _id: false,
        userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
        messagesUntil: { type: Date, default: null },
        callsUntil: { type: Date, default: null },
      },
    ],

    // Currently valid refresh tokens (rotated on refresh, cleared on logout).
    refreshTokens: {
      type: [String],
      default: [],
    },

    // Instant the password last changed. Access tokens issued before this are
    // rejected by verifyJWT, so a password change/reset logs out every other
    // session immediately (not just when its short-lived access token expires).
    passwordChangedAt: {
      type: Date,
      default: null,
    },

    // Password reset — we store only SHA-256 hashes of the OTP / link token /
    // one-time ticket, never the raw values. A single shared expiry governs the
    // whole reset attempt; otpAttempts bounds brute-forcing the 6-digit code.
    passwordReset: {
      otpHash: { type: String, default: undefined }, // sha256(6-digit OTP)
      linkTokenHash: { type: String, default: undefined }, // sha256(emailed link token)
      ticketHash: { type: String, default: undefined }, // sha256(ticket from verify-otp)
      expiresAt: { type: Date, default: undefined },
      otpAttempts: { type: Number, default: 0 },
    },

    // Email verification. Defaults to TRUE so social sign-ins and any account
    // predating this feature are treated as verified; email/password register
    // explicitly sets it false and gates login until the OTP is confirmed. Only
    // the SHA-256 hash of the code is stored.
    isEmailVerified: {
      type: Boolean,
      default: true,
    },
    emailVerification: {
      otpHash: { type: String, default: undefined }, // sha256(6-digit OTP)
      expiresAt: { type: Date, default: undefined },
      otpAttempts: { type: Number, default: 0 },
    },
  },
  { timestamps: true }
);

// Every account must be reachable by at least one credential: a password or a
// linked social identity. Guards against accidentally creating a login-less user.
userSchema.pre('validate', function (next) {
  if (!this.passwordHash && !this.firebaseUid) {
    this.invalidate('passwordHash', 'A password or a linked social account is required');
  }
  next();
});

// ---- Password helpers ----

// Hash a plaintext password and store it. Call before save when password set.
userSchema.methods.setPassword = async function (plainPassword) {
  this.passwordHash = await bcrypt.hash(plainPassword, 10);
  // Back-date by 1s so a token minted right after (e.g. tokens issued at the end
  // of registration) isn't falsely rejected by second-resolution JWT `iat`.
  this.passwordChangedAt = new Date(Date.now() - 1000);
};

// Compare a candidate password against the stored hash.
userSchema.methods.isPasswordCorrect = async function (plainPassword) {
  return bcrypt.compare(plainPassword, this.passwordHash);
};

// True if the password changed after the given JWT `iat` (unix seconds) — i.e.
// the token predates the latest password change and must be rejected.
userSchema.methods.changedPasswordAfter = function (jwtIatSeconds) {
  if (!this.passwordChangedAt) return false;
  const changedSeconds = Math.floor(this.passwordChangedAt.getTime() / 1000);
  return jwtIatSeconds < changedSeconds;
};

// ---- JWT helpers ----

userSchema.methods.generateAccessToken = function () {
  return jwt.sign(
    {
      _id: this._id,
      email: this.email,
      username: this.username,
    },
    process.env.ACCESS_TOKEN_SECRET,
    { expiresIn: process.env.ACCESS_TOKEN_EXPIRY || '15m' }
  );
};

userSchema.methods.generateRefreshToken = function (expiresIn) {
  return jwt.sign(
    { _id: this._id },
    process.env.REFRESH_TOKEN_SECRET,
    { expiresIn: expiresIn || process.env.REFRESH_TOKEN_EXPIRY || '365d' }
  );
};

// Strip sensitive fields before sending a user object to the client.
userSchema.methods.toSafeObject = function () {
  return {
    _id: this._id,
    email: this.email,
    displayName: this.displayName,
    username: this.username,
    usernameChangedAt: this.usernameChangedAt,
    avatar: this.avatar,
    bio: this.bio,
    contacts: this.contacts,
    isOnline: this.isOnline,
    lastSeenAt: this.lastSeenAt,
    showOnlineStatus: this.showOnlineStatus,
    showLastSeen: this.showLastSeen,
    receiveCalls: this.receiveCalls,
    isEmailVerified: this.isEmailVerified,
    mutedUsers: (this.mutedUsers || []).map((m) => ({
      userId: m.userId,
      messagesUntil: m.messagesUntil,
      callsUntil: m.callsUntil,
    })),
    // Lets the client show "set a password" (Google-only) vs "change password".
    hasPassword: Boolean(this.passwordHash),
    createdAt: this.createdAt,
  };
};

export const User = mongoose.model('User', userSchema);
