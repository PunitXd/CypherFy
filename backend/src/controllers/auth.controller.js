// Auth controller — register, login, logout, refresh, forgot/reset password.
//
// Tokens: a short-lived access token (15m) and a rotating refresh token whose
// lifetime depends on the client platform (web 7d, mobile 365d — see
// refreshExpiryFor). Refresh tokens are persisted so they can be individually revoked.
// Both are also set as httpOnly cookies for browser clients; the JSON body
// carries them too for the Flutter secure-storage flow.

import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import { User } from '../models/user.model.js';
import { ApiError } from '../utils/ApiError.js';
import { ApiResponse } from '../utils/ApiResponse.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import {
  sendPasswordResetEmail,
  sendVerificationEmail,
} from '../services/email.service.js';
import {
  verifyFirebaseToken,
  isFirebaseConfigured,
} from '../services/firebase.service.js';
import { resetAuthAttempts } from '../services/redis.service.js';
import { PASSWORD_RESET, EMAIL_VERIFICATION } from '../constants.js';

// SHA-256 hex of a raw secret (OTP / link token / ticket). We persist only the
// hash so a DB leak never exposes a usable reset credential.
const sha256 = (raw) => crypto.createHash('sha256').update(raw).digest('hex');

// Clear a user's pending reset attempt. Overwrites the nested leaves rather than
// assigning `undefined` to the path — Mongoose won't unset a nested path that
// way, and a lingering ticket/link hash would allow token reuse.
const clearPasswordReset = (user) => {
  user.passwordReset = {
    otpHash: undefined,
    linkTokenHash: undefined,
    ticketHash: undefined,
    expiresAt: undefined,
    otpAttempts: 0,
  };
};

// A fresh zero-padded numeric OTP of the given length.
const genOtp = (length) =>
  String(crypto.randomInt(0, 10 ** length)).padStart(length, '0');

// Overwrite (not unset) the nested email-verification leaves — same Mongoose
// caveat as clearPasswordReset.
const clearEmailVerification = (user) => {
  user.emailVerification = {
    otpHash: undefined,
    expiresAt: undefined,
    otpAttempts: 0,
  };
};

// Generate a verification OTP, store its hash on the user, and email the code.
// Caller is responsible for saving the user.
const issueVerificationOtp = async (user) => {
  const otp = genOtp(EMAIL_VERIFICATION.OTP_LENGTH);
  user.emailVerification = {
    otpHash: sha256(otp),
    expiresAt: new Date(Date.now() + EMAIL_VERIFICATION.TTL_MS),
    otpAttempts: 0,
  };
  await user.save({ validateBeforeSave: false });
  await sendVerificationEmail(user.email, { otp });
};

// httpOnly cookie options — not readable by JS, sent only over same-site.
const cookieOptions = {
  httpOnly: true,
  secure: process.env.NODE_ENV === 'production',
  sameSite: 'lax',
};

// Generate a fresh access+refresh pair and persist the refresh token.
// Refresh-token lifetime by platform: WEB stays short (sessions on shared/public
// machines shouldn't linger), MOBILE stays signed in long-term. The client
// declares itself via the `X-Client-Platform` header.
const WEB_REFRESH_EXPIRY = '7d';
const refreshExpiryFor = (req) =>
  req.get('X-Client-Platform') === 'web'
    ? WEB_REFRESH_EXPIRY
    : process.env.REFRESH_TOKEN_EXPIRY || '365d';

const issueTokens = async (user, refreshExpiry) => {
  const accessToken = user.generateAccessToken();
  const refreshToken = user.generateRefreshToken(refreshExpiry);
  user.refreshTokens.push(refreshToken);
  await user.save({ validateBeforeSave: false });
  return { accessToken, refreshToken };
};

// POST /api/v1/auth/register
export const register = asyncHandler(async (req, res) => {
  const { email, password, displayName, username } = req.body;

  if (!email || !password || !displayName || !username) {
    throw new ApiError(400, 'email, password, displayName and username are required');
  }
  if (password.length < 8) {
    throw new ApiError(400, 'Password must be at least 8 characters');
  }

  const emailLower = email.toLowerCase();
  const usernameLower = username.toLowerCase();

  // A verified account already owns this email → real conflict. An UNVERIFIED
  // account with this email can be reclaimed (someone re-registering before
  // confirming), so we reuse that doc rather than blocking the address forever.
  const byEmail = await User.findOne({ email: emailLower });
  if (byEmail && byEmail.isEmailVerified) {
    throw new ApiError(409, 'A user with that email already exists');
  }
  // The username must be free, ignoring the reclaimable same-email doc.
  const byUsername = await User.findOne({ username: usernameLower });
  if (byUsername && String(byUsername.email) !== emailLower) {
    throw new ApiError(409, 'That username is already taken');
  }

  const user = byEmail || new User({ email: emailLower });
  user.displayName = displayName;
  user.username = usernameLower;
  await user.setPassword(password); // bcrypt hash — never store plaintext
  user.isEmailVerified = false; // gate access until the emailed OTP is confirmed
  clearPasswordReset(user);

  // Persist + email a verification code. No tokens are issued yet.
  await issueVerificationOtp(user);

  return res.status(201).json(
    new ApiResponse(
      201,
      { verificationRequired: true, email: user.email },
      'Verification code sent to your email'
    )
  );
});

// POST /api/v1/auth/verify-email — confirm the registration OTP and, on success,
// mark the account verified and issue session tokens (grants access).
export const verifyEmail = asyncHandler(async (req, res) => {
  const { email, otp } = req.body;
  if (!email || !otp) throw new ApiError(400, 'email and otp are required');

  const user = await User.findOne({
    email: email.toLowerCase(),
    'emailVerification.otpHash': { $type: 'string' },
  });
  if (
    !user ||
    !user.emailVerification.expiresAt ||
    user.emailVerification.expiresAt.getTime() < Date.now()
  ) {
    throw new ApiError(400, 'Code expired — please request a new one');
  }
  if (user.emailVerification.otpAttempts >= EMAIL_VERIFICATION.MAX_OTP_ATTEMPTS) {
    throw new ApiError(429, 'Too many attempts — please request a new code');
  }
  if (sha256(String(otp)) !== user.emailVerification.otpHash) {
    user.emailVerification.otpAttempts += 1;
    await user.save({ validateBeforeSave: false });
    throw new ApiError(400, 'Incorrect code');
  }

  // Correct → verify + clear the pending code, then issue tokens.
  user.isEmailVerified = true;
  clearEmailVerification(user);
  const { accessToken, refreshToken } = await issueTokens(user, refreshExpiryFor(req));

  return res
    .status(200)
    .cookie('accessToken', accessToken, cookieOptions)
    .cookie('refreshToken', refreshToken, cookieOptions)
    .json(
      new ApiResponse(
        200,
        { user: user.toSafeObject(), accessToken, refreshToken },
        'Email verified'
      )
    );
});

// POST /api/v1/auth/resend-verification — email a fresh code. Always 200 (never
// reveals whether the address exists / is already verified).
export const resendVerification = asyncHandler(async (req, res) => {
  const { email } = req.body;
  if (!email) throw new ApiError(400, 'email is required');
  const user = await User.findOne({ email: email.toLowerCase() });
  if (user && !user.isEmailVerified) {
    await issueVerificationOtp(user);
  }
  return res
    .status(200)
    .json(new ApiResponse(200, { sent: true }, 'If that account needs verifying, a code was sent'));
});

// POST /api/v1/auth/login
export const login = asyncHandler(async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) {
    throw new ApiError(400, 'email and password are required');
  }

  const user = await User.findOne({ email: email.toLowerCase() });
  if (!user || !(await user.isPasswordCorrect(password))) {
    // Same message for both cases — don't reveal which accounts exist.
    throw new ApiError(401, 'Invalid credentials');
  }

  // Registered but never confirmed the emailed code → don't grant access. Send a
  // fresh code and tell the client to route to the verification screen.
  if (!user.isEmailVerified) {
    await issueVerificationOtp(user);
    return res.status(403).json(
      new ApiResponse(
        403,
        { verificationRequired: true, email: user.email },
        'Please verify your email — we sent you a new code'
      )
    );
  }

  const { accessToken, refreshToken } = await issueTokens(user, refreshExpiryFor(req));

  // Genuine success clears any auth backoff for this IP + account, so a user who
  // fat-fingered their password a few times isn't left throttled. Best-effort.
  resetAuthAttempts([
    ['ip', req.ip],
    ['account', email.toLowerCase()],
  ]).catch(() => {});

  return res
    .status(200)
    .cookie('accessToken', accessToken, cookieOptions)
    .cookie('refreshToken', refreshToken, cookieOptions)
    .json(
      new ApiResponse(
        200,
        { user: user.toSafeObject(), accessToken, refreshToken },
        'Logged in successfully'
      )
    );
});

// Build a unique username from an email local-part: slugify, then append a
// numeric suffix until it's free. Kept small and deterministic for testing.
export const generateUsername = async (email) => {
  const base =
    (email || '')
      .split('@')[0]
      .toLowerCase()
      .replace(/[^a-z0-9_]/g, '')
      .slice(0, 20) || 'user';
  let candidate = base;
  for (let i = 0; i < 50; i += 1) {
    // eslint-disable-next-line no-await-in-loop
    const taken = await User.exists({ username: candidate });
    if (!taken) return candidate;
    candidate = `${base}${Math.floor(1000 + Math.random() * 9000)}`;
  }
  // Extremely unlikely fallback — guaranteed-unique suffix.
  return `${base}${Date.now()}`;
};

// Find-or-create a user for a verified social identity, keyed by [uidField]
// (e.g. 'firebaseUid'). Order matters:
//   1. match by the provider uid → returning social user
//   2. else match by email       → link the identity to an existing account
//   3. else create a new password-less account
// Exported so it can be unit-tested without a real provider token.
export const upsertSocialUser = async ({ uidField, uid, email, name, avatar }) => {
  const lowerEmail = (email || '').toLowerCase();

  let user = await User.findOne({ [uidField]: uid });
  if (user) return user;

  user = await User.findOne({ email: lowerEmail });
  if (user) {
    // Link the social identity to the existing account; backfill empties.
    user[uidField] = uid;
    if (!user.avatar && avatar) user.avatar = avatar;
    if (!user.displayName && name) user.displayName = name;
    await user.save();
    return user;
  }

  user = new User({
    email: lowerEmail,
    [uidField]: uid,
    displayName: name || lowerEmail.split('@')[0],
    username: await generateUsername(lowerEmail),
    avatar: avatar || null,
  });
  await user.save();
  return user;
};

// POST /api/v1/auth/firebase  { idToken }
// Verify a Firebase ID token (from any social provider wired in Firebase — the
// client signs in with Google/Apple/… and Firebase mints one token type), then
// upsert the user and issue OUR tokens. Downstream this is identical to login.
export const firebaseAuth = asyncHandler(async (req, res) => {
  const { idToken } = req.body;
  if (!idToken) throw new ApiError(400, 'idToken is required');

  if (!isFirebaseConfigured()) {
    throw new ApiError(500, 'Firebase auth is not configured');
  }

  let decoded;
  try {
    decoded = await verifyFirebaseToken(idToken);
  } catch {
    throw new ApiError(401, 'Invalid Firebase token');
  }

  // Firebase verifies the email with the underlying provider. Apple may return
  // a private-relay address; that's fine — it's still a stable, verified email.
  if (!decoded.email) {
    throw new ApiError(401, 'Google/Apple account did not provide an email');
  }

  const user = await upsertSocialUser({
    uidField: 'firebaseUid',
    uid: decoded.uid,
    email: decoded.email,
    name: decoded.name,
    avatar: decoded.picture,
  });
  const { accessToken, refreshToken } = await issueTokens(user, refreshExpiryFor(req));

  return res
    .status(200)
    .cookie('accessToken', accessToken, cookieOptions)
    .cookie('refreshToken', refreshToken, cookieOptions)
    .json(
      new ApiResponse(
        200,
        { user: user.toSafeObject(), accessToken, refreshToken },
        'Signed in'
      )
    );
});

// POST /api/v1/auth/logout  (auth required)
export const logout = asyncHandler(async (req, res) => {
  const incoming = req.cookies?.refreshToken || req.body?.refreshToken;

  if (incoming && req.user) {
    // Revoke just this device's refresh token. verifyJWT loads req.user
    // WITHOUT refreshTokens (it's deselected), so pull atomically rather than
    // reading the array off req.user — filtering a missing field would wipe
    // every device's token.
    await User.updateOne(
      { _id: req.user._id },
      { $pull: { refreshTokens: incoming } }
    );
  }

  return res
    .status(200)
    .clearCookie('accessToken', cookieOptions)
    .clearCookie('refreshToken', cookieOptions)
    .json(new ApiResponse(200, {}, 'Logged out'));
});

// POST /api/v1/auth/change-password  (auth required)
// Authenticated password change: verify the current password, set the new one,
// and revoke every OTHER session (keep the caller's current one alive).
export const changePassword = asyncHandler(async (req, res) => {
  const { currentPassword, newPassword } = req.body;
  if (!currentPassword || !newPassword) {
    throw new ApiError(400, 'currentPassword and newPassword are required');
  }
  if (newPassword.length < 8) {
    throw new ApiError(400, 'Password must be at least 8 characters');
  }

  // verifyJWT loads req.user without passwordHash/refreshTokens — re-fetch the
  // full doc so we can verify and rotate sessions.
  const user = await User.findById(req.user._id);
  if (!user) throw new ApiError(404, 'User not found');

  const ok = await user.isPasswordCorrect(currentPassword);
  if (!ok) throw new ApiError(400, 'Current password is incorrect');

  await user.setPassword(newPassword);
  // Keep only the caller's current refresh token (sent in body/cookie); this
  // signs out other devices. If we can't identify it, revoke all to be safe.
  const incoming = req.cookies?.refreshToken || req.body?.refreshToken;
  user.refreshTokens = incoming
    ? user.refreshTokens.filter((t) => t === incoming)
    : [];
  await user.save();

  return res
    .status(200)
    .json(new ApiResponse(200, {}, 'Password changed successfully'));
});

// POST /api/v1/auth/refresh-token  (rotates the refresh token)
export const refreshToken = asyncHandler(async (req, res) => {
  const incoming = req.cookies?.refreshToken || req.body?.refreshToken;
  if (!incoming) throw new ApiError(401, 'No refresh token provided');

  let decoded;
  try {
    decoded = jwt.verify(incoming, process.env.REFRESH_TOKEN_SECRET);
  } catch {
    throw new ApiError(401, 'Invalid or expired refresh token');
  }

  const user = await User.findById(decoded._id);
  // Token must exist in the user's active set — otherwise it was revoked/reused.
  if (!user || !user.refreshTokens.includes(incoming)) {
    throw new ApiError(401, 'Refresh token has been revoked');
  }

  // Rotate: drop the old token, issue a new pair.
  user.refreshTokens = user.refreshTokens.filter((t) => t !== incoming);
  const { accessToken, refreshToken: newRefresh } = await issueTokens(user, refreshExpiryFor(req));

  return res
    .status(200)
    .cookie('accessToken', accessToken, cookieOptions)
    .cookie('refreshToken', newRefresh, cookieOptions)
    .json(
      new ApiResponse(
        200,
        { accessToken, refreshToken: newRefresh },
        'Token refreshed'
      )
    );
});

// Password reset is a two-step OTP flow that also supports an emailed link:
//   forgot-password  → email a 6-digit OTP + a link token (both hashed on the doc)
//   verify-otp       → exchange the OTP for a one-time ticket
//   reset-password   → set a new password using the ticket OR the link token
// Only hashes are stored; a single shared expiry governs the whole attempt.

// POST /api/v1/auth/forgot-password
export const forgotPassword = asyncHandler(async (req, res) => {
  const { email } = req.body;
  if (!email) throw new ApiError(400, 'email is required');

  const user = await User.findOne({ email: email.toLowerCase() });

  // Always respond 200 — never reveal whether the email is registered.
  if (user) {
    // 6-digit numeric OTP for in-app entry; long random token for the web link.
    const otp = String(crypto.randomInt(0, 10 ** PASSWORD_RESET.OTP_LENGTH)).padStart(
      PASSWORD_RESET.OTP_LENGTH,
      '0'
    );
    const linkToken = crypto.randomBytes(32).toString('hex');

    user.passwordReset = {
      otpHash: sha256(otp),
      linkTokenHash: sha256(linkToken),
      ticketHash: undefined,
      expiresAt: new Date(Date.now() + PASSWORD_RESET.TTL_MS),
      otpAttempts: 0,
    };
    await user.save({ validateBeforeSave: false });

    // The React web app uses history (BrowserRouter) routing — the reset screen
    // lives at /reset and reads token+email from the query string. (CLIENT_URL
    // must point at the deployed web frontend for this link to resolve.)
    const resetUrl = `${process.env.CLIENT_URL}/reset?token=${linkToken}&email=${encodeURIComponent(user.email)}`;
    // A mail outage must not 500 the request (nor leak that the account exists).
    // Log and still return the generic 200 below.
    try {
      await sendPasswordResetEmail(user.email, { otp, resetUrl });
    } catch (err) {
      console.error('forgot-password: email send failed:', err.message);
    }
  }

  return res
    .status(200)
    .json(
      new ApiResponse(200, {}, 'If that email exists, a reset code has been sent')
    );
});

// POST /api/v1/auth/verify-otp — validate the code, hand back a one-time ticket.
export const verifyOtp = asyncHandler(async (req, res) => {
  const { email, otp } = req.body;
  if (!email || !otp) throw new ApiError(400, 'email and otp are required');

  const user = await User.findOne({
    email: email.toLowerCase(),
    'passwordReset.otpHash': { $type: 'string' },
    'passwordReset.expiresAt': { $gt: new Date() },
  });
  if (!user) throw new ApiError(400, 'Invalid or expired code');

  // Bound brute-forcing the 6-digit code: invalidate the whole attempt at the cap.
  if (user.passwordReset.otpAttempts >= PASSWORD_RESET.MAX_OTP_ATTEMPTS) {
    clearPasswordReset(user);
    await user.save({ validateBeforeSave: false });
    throw new ApiError(400, 'Too many attempts — request a new code');
  }

  if (sha256(String(otp)) !== user.passwordReset.otpHash) {
    user.passwordReset.otpAttempts += 1;
    await user.save({ validateBeforeSave: false });
    throw new ApiError(400, 'Invalid or expired code');
  }

  // Correct: consume the OTP and issue a fresh single-use ticket so the raw code
  // is never re-sent alongside the new password.
  const ticket = crypto.randomBytes(32).toString('hex');
  user.passwordReset.ticketHash = sha256(ticket);
  user.passwordReset.otpHash = undefined;
  user.passwordReset.otpAttempts = 0;
  user.passwordReset.expiresAt = new Date(Date.now() + PASSWORD_RESET.TTL_MS);
  await user.save({ validateBeforeSave: false });

  return res
    .status(200)
    .json(new ApiResponse(200, { ticket }, 'Code verified'));
});

// POST /api/v1/auth/reset-password
export const resetPassword = asyncHandler(async (req, res) => {
  const { email, token, newPassword } = req.body;
  if (!email || !token || !newPassword) {
    throw new ApiError(400, 'email, token and newPassword are required');
  }
  if (newPassword.length < 8) {
    throw new ApiError(400, 'Password must be at least 8 characters');
  }

  // `token` is either the verify-otp ticket (in-app) or the emailed link token.
  const tokenHash = sha256(token);
  const user = await User.findOne({
    email: email.toLowerCase(),
    'passwordReset.expiresAt': { $gt: new Date() },
    $or: [
      { 'passwordReset.ticketHash': tokenHash },
      { 'passwordReset.linkTokenHash': tokenHash },
    ],
  });
  if (!user) throw new ApiError(400, 'Invalid or expired token');

  await user.setPassword(newPassword);
  clearPasswordReset(user); // one-time — consume the whole attempt
  // Force re-login everywhere after a password reset.
  user.refreshTokens = [];
  await user.save();

  // NOTE: room keys are derived from roomId (not the password) in the current
  // model, so a password change does NOT orphan any encrypted room data. If keys
  // ever become password-wrapped, a client-side re-wrap step must be added here.

  return res
    .status(200)
    .json(new ApiResponse(200, {}, 'Password reset successful — please log in'));
});
