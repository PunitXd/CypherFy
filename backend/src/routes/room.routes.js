// Room routes — /api/v1/rooms
// Ephemeral create/validate are public (guests). Permanent routes need auth.

import { Router } from 'express';
import {
  createEphemeralRoom,
  getPermanentRooms,
  getRoomByCode,
  deletePermanentRoom,
} from '../controllers/room.controller.js';
import { verifyJWT, optionalAuth } from '../middlewares/auth.middleware.js';
import { publicLimiter, userLimiter } from '../middlewares/rateLimit.middleware.js';
import { validate } from '../middlewares/validate.middleware.js';
import { roomSchemas } from '../validators/http.schemas.js';

const router = Router();

// Public — ephemeral rooms (guests included). Moderate per-IP limit.
router.post('/', publicLimiter, validate(roomSchemas.createEphemeral), optionalAuth, createEphemeralRoom);

// Auth — permanent DM rooms. Declared BEFORE the /:code wildcard so "permanent"
// isn't captured as a room code.
router.get('/permanent', verifyJWT, userLimiter, getPermanentRooms);
router.delete('/permanent/:roomId', verifyJWT, userLimiter, validate(roomSchemas.roomIdParam), deletePermanentRoom);

// Public — validate an ephemeral code (wildcard last). Moderate per-IP limit
// also blunts room-code guessing over HTTP.
router.get('/:code', publicLimiter, validate(roomSchemas.codeParam), getRoomByCode);

export default router;
