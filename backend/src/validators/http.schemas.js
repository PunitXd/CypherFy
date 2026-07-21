// Strict zod schemas for every HTTP endpoint, grouped by router. Each entry is
// { body?, query?, params? }; the validate() middleware rejects any request that
// doesn't match (wrong type/length/format, missing required field, OR unknown
// key — every object is a strictObject).

import { z } from 'zod';
import {
  zEmail,
  zNewPassword,
  zAuthPassword,
  zUsername,
  zDisplayName,
  zBio,
  zOtp,
  zResetToken,
  zIdToken,
  zRefreshToken,
  zMongoId,
  zCallId,
  zRoomCode,
  zAlias,
  zRoomName,
  zMaxUsers,
  zTtlSeconds,
  zPassHint,
  zBlobName,
  zTimestampMs,
} from './common.js';

// ---- Auth (/api/v1/auth) -----------------------------------------------
export const authSchemas = {
  register: {
    body: z.strictObject({
      email: zEmail,
      password: zNewPassword,
      displayName: zDisplayName,
      username: zUsername,
    }),
  },
  verifyEmail: { body: z.strictObject({ email: zEmail, otp: zOtp }) },
  resendVerification: { body: z.strictObject({ email: zEmail }) },
  login: { body: z.strictObject({ email: zEmail, password: zAuthPassword }) },
  firebase: { body: z.strictObject({ idToken: zIdToken }) },
  // refreshToken may arrive via httpOnly cookie instead of the body, and clients
  // send it as null when they have none — accept both. Used by logout + refresh.
  refreshToken: { body: z.strictObject({ refreshToken: zRefreshToken.nullable().optional() }) },
  changePassword: {
    body: z.strictObject({
      currentPassword: zAuthPassword,
      newPassword: zNewPassword,
      // Clients pass the current refresh token so this session survives while
      // others are revoked; may be null when none is stored.
      refreshToken: zRefreshToken.nullable().optional(),
    }),
  },
  forgotPassword: { body: z.strictObject({ email: zEmail }) },
  verifyOtp: { body: z.strictObject({ email: zEmail, otp: zOtp }) },
  resetPassword: {
    body: z.strictObject({ email: zEmail, token: zResetToken, newPassword: zNewPassword }),
  },
};

// ---- Users (/api/v1/users) ---------------------------------------------
export const userSchemas = {
  updateMe: {
    body: z
      .strictObject({
        displayName: zDisplayName.optional(),
        bio: zBio.optional(),
        username: zUsername.optional(),
        showOnlineStatus: z.boolean().optional(),
        showLastSeen: z.boolean().optional(),
        receiveCalls: z.boolean().optional(),
      })
      .refine((o) => Object.keys(o).length > 0, 'No fields to update'),
  },
  deleteAccount: { body: z.strictObject({ password: zAuthPassword }) },
  // The controller tolerates an empty/absent term (returns no results), so don't
  // hard-reject it; still bound the type and length.
  search: { query: z.strictObject({ q: z.string().max(100).optional() }) },
  userIdParam: { params: z.strictObject({ userId: zMongoId }) },
  setMute: {
    params: z.strictObject({ userId: zMongoId }),
    body: z
      .strictObject({
        messagesUntil: zTimestampMs.nullable().optional(),
        callsUntil: zTimestampMs.nullable().optional(),
      })
      .refine(
        (o) => o.messagesUntil !== undefined || o.callsUntil !== undefined,
        'Provide messagesUntil and/or callsUntil'
      ),
  },
};

// ---- Chat requests (/api/v1/requests) ----------------------------------
export const requestSchemas = {
  send: { body: z.strictObject({ toUserId: zMongoId }) },
  requestIdParam: { params: z.strictObject({ requestId: zMongoId }) },
};

// ---- Rooms (/api/v1/rooms) ---------------------------------------------
export const roomSchemas = {
  createEphemeral: {
    body: z.strictObject({
      createdBy: zAlias,
      name: zRoomName.optional(),
      maxUsers: zMaxUsers.optional(),
      isLocked: z.boolean().optional(),
      passHint: zPassHint.nullable().optional(),
      ttlSeconds: zTtlSeconds.optional(),
    }),
  },
  codeParam: { params: z.strictObject({ code: zRoomCode }) },
  roomIdParam: { params: z.strictObject({ roomId: zMongoId }) },
};

// ---- Upload (/api/v1/upload) -------------------------------------------
export const uploadSchemas = {
  presignedPut: { query: z.strictObject({ blobName: zBlobName.optional() }) },
  presignedGet: { query: z.strictObject({ blobName: zBlobName }) },
};

// ---- Calls (/api/v1/calls) ---------------------------------------------
export const callSchemas = {
  rejectParam: { params: z.strictObject({ callId: zCallId }) },
};
