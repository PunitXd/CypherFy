// Reusable zod field primitives shared by the HTTP and socket schemas.
//
// Design: validate TYPE, LENGTH, and FORMAT strictly and REJECT anything that
// doesn't match — never silently sanitize. Opaque E2E-encrypted blobs
// (ciphertext, IVs, wrapped keys) are validated for SHAPE only (non-empty,
// bounded length, base64 charset); their contents are never inspected.
// Object schemas everywhere use z.strictObject so unknown keys are rejected.

import { z } from 'zod';
import { ROOM, FILE, PASSWORD_RESET } from '../constants.js';

// ---- Identity / account fields -----------------------------------------
export const zEmail = z.email().max(254).transform((v) => v.toLowerCase());
export const zNewPassword = z.string().min(8).max(128); // registration / reset
export const zAuthPassword = z.string().min(1).max(128); // login / confirm (don't leak policy)
export const zUsername = z
  .string()
  .trim()
  .min(3)
  .max(20)
  .regex(/^[A-Za-z0-9_]+$/, 'Username may use only letters, numbers, or underscores')
  .transform((v) => v.toLowerCase());
export const zDisplayName = z.string().trim().min(1).max(50);
export const zBio = z.string().max(300);
export const zOtp = z.string().regex(new RegExp(`^\\d{${PASSWORD_RESET.OTP_LENGTH}}$`), 'OTP must be 6 digits');
export const zResetToken = z.string().min(16).max(256); // hex ticket or emailed link token
export const zIdToken = z.string().min(1).max(8192); // Firebase ID token (JWT)
export const zRefreshToken = z.string().min(1).max(2048);

// ---- Ids ---------------------------------------------------------------
export const zMongoId = z.string().regex(/^[a-fA-F0-9]{24}$/, 'Invalid id');
export const zCallId = z.uuid();

// ---- Rooms -------------------------------------------------------------
export const zRoomCode = z
  .string()
  .trim()
  .length(ROOM.CODE_LENGTH)
  .regex(/^[A-Za-z0-9]+$/, 'Invalid room code')
  .transform((v) => v.toUpperCase());
export const zAlias = z.string().trim().min(1).max(40);
export const zRoomName = z.string().trim().min(1).max(60);
export const zMaxUsers = z.number().int().min(2).max(10);
export const zTtlSeconds = z.number().int().min(60).max(ROOM.TTL_OPTIONS['7d']);
export const zPassHint = z.string().max(100);

// ---- Opaque encrypted blobs (shape only) -------------------------------
// Standard and URL-safe base64 alphabets, plus '=' padding.
const BASE64 = /^[A-Za-z0-9+/=_-]+$/;
const zB64 = (max) => z.string().min(1).max(max).regex(BASE64, 'Expected base64 data');
export const zCiphertext = zB64(200_000); // one encrypted message (generous cap)
export const zIv = zB64(64);
export const zEncMeta = zB64(8_000); // encrypted file-metadata blob
export const zFileSize = z.number().int().nonnegative().max(FILE.MAX_SIZE_BYTES);

// Object storage key. The server usually mints this; when a client supplies one
// it must be a safe relative key (no traversal, no absolute paths).
export const zBlobName = z
  .string()
  .min(1)
  .max(200)
  .regex(/^[A-Za-z0-9/_.\-]+$/, 'Invalid blob name')
  .refine((s) => !s.includes('..'), 'Invalid blob name');

// ---- Misc --------------------------------------------------------------
export const zEmoji = z.string().min(1).max(16);
export const zFcmToken = z.string().min(1).max(4096);
export const zTimestampMs = z.number().int().nonnegative();

// Opaque WebRTC signalling blobs relayed verbatim between peers. We bound size
// and require the expected shape but never interpret SDP/ICE contents.
export const zSdp = z.union([z.string().max(20_000), z.record(z.string(), z.unknown())]);
export const zIceCandidate = z.union([z.string().max(4_000), z.record(z.string(), z.unknown())]);
export const zSocketId = z.string().min(1).max(64);
