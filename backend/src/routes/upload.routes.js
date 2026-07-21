// Upload routes — /api/v1/upload

import { Router } from 'express';
import {
  getPresignedPut,
  getPresignedGet,
  uploadAvatarFile,
} from '../controllers/upload.controller.js';
import { verifyJWT } from '../middlewares/auth.middleware.js';
import { upload } from '../middlewares/multer.middleware.js';
import { publicLimiter, userLimiter } from '../middlewares/rateLimit.middleware.js';
import { validate } from '../middlewares/validate.middleware.js';
import { uploadSchemas } from '../validators/http.schemas.js';

const router = Router();

// Presigned URLs — intentionally open to guests: ephemeral-room files are E2E
// encrypted with random blob names, and traffic is rate-limited. Requiring auth
// here would block anonymous ephemeral rooms from sending files at all.
router.get('/presigned-put', publicLimiter, validate(uploadSchemas.presignedPut), getPresignedPut);
router.get('/presigned-get', publicLimiter, validate(uploadSchemas.presignedGet), getPresignedGet);

// Avatar upload via multer (field name: "avatar"). The file itself is validated
// by multer (type/size); there are no other body fields.
router.post('/avatar', verifyJWT, userLimiter, upload.single('avatar'), uploadAvatarFile);

export default router;
