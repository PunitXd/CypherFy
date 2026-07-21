// Message model — stores ONLY ciphertext. The server can never read message
// content: text lives as { ciphertext, iv }, files as an encrypted R2 blob plus
// encrypted metadata. Reactions and reply pointers are the only cleartext.

import mongoose, { Schema } from 'mongoose';

const messageSchema = new Schema(
  {
    roomId: {
      type: Schema.Types.ObjectId,
      ref: 'Room',
      required: true,
    },
    type: {
      type: String,
      enum: ['text', 'file'],
      default: 'text',
    },

    // Display identity of the sender: alias (ephemeral) or display name.
    senderAlias: {
      type: String,
      required: true,
    },
    // Account user id, when the sender is logged in. null for anonymous.
    senderId: {
      type: Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },

    // ---- Text message (encrypted) ----
    ciphertext: { type: String },
    iv: { type: String },

    // ---- File message (encrypted) ----
    blobName: { type: String }, // random object name in R2
    encMeta: { type: String }, // AES-GCM encrypted JSON { name, type }
    metaIv: { type: String },
    size: { type: Number }, // raw byte size — the only unencrypted file field

    // ---- Features ----
    replyTo: {
      type: Schema.Types.ObjectId,
      ref: 'Message',
      default: null,
    },
    // Emoji → count, e.g. { "👍": 3 }.
    reactions: {
      type: Map,
      of: Number,
      default: {},
    },

    // Soft delete (your-side-only for permanent rooms). A message is hidden
    // from any user whose id appears here.
    deletedFor: [
      {
        type: Schema.Types.ObjectId,
        ref: 'User',
      },
    ],

    // ---- Read receipts ----
    // Recipient identifiers who have received / read this message (the sender is
    // never listed). Identifier = userId (permanent DMs) or alias (ephemeral
    // rooms). readBy ⊆ deliveredTo. Drives the client's ✓ / ✓✓ / blue ✓✓ ticks.
    deliveredTo: { type: [String], default: [] },
    readBy: { type: [String], default: [] },
  },
  { timestamps: true }
);

// Primary read pattern: fetch a room's messages in chronological order.
messageSchema.index({ roomId: 1, createdAt: 1 });

export const Message = mongoose.model('Message', messageSchema);
