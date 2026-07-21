// User routes — /api/v1/users (all require auth)

import { Router } from 'express';
import {
  getMe,
  updateMe,
  deleteAccount,
  searchUsers,
  getPublicProfile,
  getContacts,
  addContact,
  removeContact,
  setMute,
} from '../controllers/user.controller.js';
import { verifyJWT } from '../middlewares/auth.middleware.js';
import { userLimiter } from '../middlewares/rateLimit.middleware.js';
import { validate } from '../middlewares/validate.middleware.js';
import { userSchemas } from '../validators/http.schemas.js';

const router = Router();

// Everything below requires a valid access token, then a loose per-account limit.
router.use(verifyJWT);
router.use(userLimiter);

router.get('/me', getMe);
router.patch('/me', validate(userSchemas.updateMe), updateMe);
router.delete('/me', validate(userSchemas.deleteAccount), deleteAccount);
router.get('/search', validate(userSchemas.search), searchUsers);
router.get('/contacts', getContacts);

// Contact mutation on a specific user.
router.post('/:userId/contact', validate(userSchemas.userIdParam), addContact);
router.delete('/:userId/contact', validate(userSchemas.userIdParam), removeContact);

// Per-user mute (messages and/or calls).
router.put('/:userId/mute', validate(userSchemas.setMute), setMute);

// Keep the wildcard profile route last so it doesn't shadow /me, /search, etc.
router.get('/:userId', validate(userSchemas.userIdParam), getPublicProfile);

export default router;
