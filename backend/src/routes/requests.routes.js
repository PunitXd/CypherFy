// Chat request routes — /api/v1/requests (all require auth).
// Handlers live in user.controller.js (the request lifecycle is user-centric).

import { Router } from 'express';
import {
  sendChatRequest,
  getChatRequests,
  acceptChatRequest,
  rejectChatRequest,
} from '../controllers/user.controller.js';
import { verifyJWT } from '../middlewares/auth.middleware.js';
import { userLimiter } from '../middlewares/rateLimit.middleware.js';
import { validate } from '../middlewares/validate.middleware.js';
import { requestSchemas } from '../validators/http.schemas.js';

const router = Router();

router.use(verifyJWT);
router.use(userLimiter);

router.post('/', validate(requestSchemas.send), sendChatRequest);
router.get('/', getChatRequests);
router.patch('/:requestId/accept', validate(requestSchemas.requestIdParam), acceptChatRequest);
router.patch('/:requestId/reject', validate(requestSchemas.requestIdParam), rejectChatRequest);

export default router;
