// Room model — holds BOTH room types in a single collection, discriminated by
// the `type` field ('ephemeral' | 'permanent').
//
// Ephemeral rooms auto-delete via a TTL index keyed on lastActivityAt. The
// index only applies to ephemeral rooms (partial filter) so permanent DM rooms
// are never expired.

import mongoose, { Schema } from 'mongoose';

const roomSchema = new Schema(
  {
    // ---- Common ----
    type: {
      type: String,
      enum: ['ephemeral', 'permanent'],
      required: true,
    },
    name: {
      type: String,
      default: 'Cypher Room',
    },
    createdBy: {
      type: String, // alias (ephemeral) or userId string (permanent)
      required: true,
    },
    // Ephemeral host's account id when they were logged in (null for guests).
    // Lets us reach the host with a push (knock / room-expiring) while offline —
    // `createdBy` alone is an anonymous alias.
    createdByUserId: {
      type: Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },

    // ---- Ephemeral only ----
    code: {
      type: String,
      unique: true,
      sparse: true, // permanent rooms have no code
    },
    maxUsers: {
      type: Number,
      default: 2,
      min: 2,
      max: 10,
    },
    isLocked: {
      type: Boolean,
      default: false,
    },
    passHashHint: {
      type: String,
      default: null,
    },
    inactivityTTL: {
      type: Number, // seconds of inactivity before auto-delete
      default: 3600,
    },
    // TTL anchor. With expireAfterSeconds: 0 the room is deleted the moment
    // `lastActivityAt` is reached, so this field holds a FUTURE expiry
    // timestamp = now + inactivityTTL. Every activity bumps it forward, and
    // manual expiry logic pushes it to (now + inactivityTTL) again.
    lastActivityAt: {
      type: Date,
      default: Date.now,
    },
    currentUsers: {
      type: [String], // live socket IDs currently in the room
      default: [],
    },

    // ---- Permanent only ----
    participants: [
      {
        type: Schema.Types.ObjectId,
        ref: 'User',
      },
    ],
    // NOTE: the encrypted room key is stored per-user in user.model.js
    // (roomKeys array), never here — the server must never hold a raw key.
  },
  { timestamps: true }
);

// TTL index. Mongo's TTL monitor deletes a document once
// (lastActivityAt + expireAfterSeconds) < now. With expireAfterSeconds: 0 the
// document dies exactly when lastActivityAt is reached — so we store a FUTURE
// timestamp there (now + inactivityTTL) and refresh it on every activity.
// The partial filter ensures ONLY ephemeral rooms are ever expired; permanent
// DM rooms have no lastActivityAt-driven expiry.
roomSchema.index(
  { lastActivityAt: 1 },
  {
    expireAfterSeconds: 0,
    partialFilterExpression: { type: 'ephemeral' },
  }
);

// Lookup index. (The `code` field is already indexed via unique+sparse.)
roomSchema.index({ participants: 1 });

export const Room = mongoose.model('Room', roomSchema);
