// ChatRequest model — a pending "X wants to chat" invitation between two
// account users. Accepting one creates a permanent encrypted room.

import mongoose, { Schema } from 'mongoose';

const chatRequestSchema = new Schema(
  {
    from: {
      type: Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    to: {
      type: Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    status: {
      type: String,
      enum: ['pending', 'accepted', 'rejected'],
      default: 'pending',
    },
    // Auto-expire pending requests after 7 days. This is set to createdAt + 7d
    // on creation; Mongo's TTL monitor removes the doc when it is reached.
    expiresAt: {
      type: Date,
      default: () => new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
    },
  },
  { timestamps: true }
);

// TTL — remove expired requests automatically.
chatRequestSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

// Lookup: incoming requests for a user by status.
chatRequestSchema.index({ to: 1, status: 1 });
// Prevent duplicate requests between the same ordered pair.
chatRequestSchema.index({ from: 1, to: 1 }, { unique: true });

export const ChatRequest = mongoose.model('ChatRequest', chatRequestSchema);
