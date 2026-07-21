// Call routes — /api/v1/calls (all require auth)

import { Router } from 'express';
import { rejectCall } from '../controllers/call.controller.js';
import { verifyJWT } from '../middlewares/auth.middleware.js';
import { userLimiter } from '../middlewares/rateLimit.middleware.js';
import { validate } from '../middlewares/validate.middleware.js';
import { callSchemas } from '../validators/http.schemas.js';

const router = Router();

router.use(verifyJWT);
router.use(userLimiter);

// Socket-independent decline (killed/backgrounded callee with no live socket).
router.post('/:callId/reject', validate(callSchemas.rejectParam), rejectCall);

export default router;
