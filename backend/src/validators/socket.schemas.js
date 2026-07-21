// Strict zod schemas for every Socket.io event payload. Validated by
// validatePayload() before a handler touches the data; a mismatch is rejected
// (the handler bails and emits an error) rather than sanitized. Encrypted blobs
// (ciphertext/iv/encMeta) and WebRTC SDP/ICE are validated for shape only.

import { z } from 'zod';
import {
  zRoomCode,
  zAlias,
  zMongoId,
  zCallId,
  zCiphertext,
  zIv,
  zEncMeta,
  zBlobName,
  zFileSize,
  zEmoji,
  zFcmToken,
  zSocketId,
  zSdp,
  zIceCandidate,
} from './common.js';

const zCallType = z.enum(['audio', 'video']);
const zReplyTo = zMongoId.nullable().optional();

// A message/typing target is EITHER an ephemeral code OR a permanent roomId.
const targetFields = { code: zRoomCode.optional(), roomId: zMongoId.optional() };
const hasTarget = (o) => Boolean(o.code || o.roomId);

export const socketSchemas = {
  // ---- rooms ----
  createRoom: z.strictObject({
    alias: zAlias,
    name: z.string().trim().min(1).max(60).optional(),
    maxUsers: z.number().int().min(2).max(10).optional(),
    isLocked: z.boolean().optional(),
    passHint: z.string().max(100).nullable().optional(),
    ttlSeconds: z.number().int().min(60).max(604800).optional(),
  }),
  joinRoom: z.strictObject({ code: zRoomCode, alias: zAlias }),
  joinPermanent: z.strictObject({ roomId: zMongoId }),
  endRoom: z.strictObject({ roomCode: zRoomCode }),
  leaveRoom: z.strictObject({ roomCode: zRoomCode }),
  typing: z
    .strictObject(targetFields)
    .refine(hasTarget, 'code or roomId is required'),

  // ---- messages ----
  sendMessage: z
    .strictObject({ ...targetFields, ciphertext: zCiphertext, iv: zIv, replyTo: zReplyTo })
    .refine(hasTarget, 'code or roomId is required'),
  sendFile: z
    .strictObject({
      ...targetFields,
      blobName: zBlobName,
      iv: zIv,
      encMeta: zEncMeta,
      metaIv: zIv,
      size: zFileSize,
      replyTo: zReplyTo,
    })
    .refine(hasTarget, 'code or roomId is required'),
  addReaction: z.strictObject({ messageId: zMongoId, emoji: zEmoji }),
  deleteMessage: z.strictObject({ messageId: zMongoId }),
  messageSeen: z
    .strictObject({
      ...targetFields,
      upToId: zMongoId.optional(),
      state: z.enum(['delivered', 'read']),
    })
    .refine((o) => Boolean(o.code || o.roomId || o.upToId), 'a target or upToId is required'),

  // ---- knock / admission ----
  knock: z.strictObject({ code: zRoomCode, alias: zAlias }),
  admitUser: z.strictObject({ knockSocketId: zSocketId, code: zRoomCode }),
  rejectUser: z.strictObject({ knockSocketId: zSocketId, code: zRoomCode }),

  // ---- notifications / presence ----
  saveFcmToken: z.strictObject({ token: zFcmToken }),
  removeFcmToken: z.strictObject({ token: zFcmToken }),
  updateOnline: z.strictObject({ isOnline: z.boolean().optional() }),

  // ---- calls (control plane) ----
  callStart: z
    .strictObject({
      roomId: zMongoId.optional(),
      code: zRoomCode.optional(),
      callType: zCallType.optional(),
    })
    .refine((o) => Boolean(o.code || o.roomId), 'code or roomId is required'),
  callId: z.strictObject({ callId: zCallId }),
  callGroupState: z.strictObject({ code: zRoomCode }),

  // ---- WebRTC mesh relays (opaque, shape-checked) ----
  webrtcOffer: z.strictObject({ offer: zSdp, targetSocketId: zSocketId, callId: zCallId }),
  webrtcAnswer: z.strictObject({ answer: zSdp, targetSocketId: zSocketId, callId: zCallId }),
  iceCandidate: z.strictObject({
    candidate: zIceCandidate,
    targetSocketId: zSocketId,
    callId: zCallId,
  }),
};
