// Auth routes — /api/v1/auth
// Sensitive endpoints are throttled by authRateLimiter and every input is
// validated against a strict schema (reject-on-mismatch) before the controller.

import { Router } from 'express';
import {
  register,
  verifyEmail,
  resendVerification,
  login,
  firebaseAuth,
  logout,
  refreshToken,
  forgotPassword,
  verifyOtp,
  resetPassword,
  changePassword,
} from '../controllers/auth.controller.js';
import { verifyJWT } from '../middlewares/auth.middleware.js';
import { authRateLimiter } from '../middlewares/rateLimit.middleware.js';
import { validate } from '../middlewares/validate.middleware.js';
import { authSchemas } from '../validators/http.schemas.js';

const router = Router();

router.post('/register', authRateLimiter, validate(authSchemas.register), register);
router.post('/verify-email', authRateLimiter, validate(authSchemas.verifyEmail), verifyEmail);
router.post('/resend-verification', authRateLimiter, validate(authSchemas.resendVerification), resendVerification);
router.post('/login', authRateLimiter, validate(authSchemas.login), login);
router.post('/firebase', authRateLimiter, validate(authSchemas.firebase), firebaseAuth);
router.post('/logout', verifyJWT, validate(authSchemas.refreshToken), logout);
router.post('/change-password', authRateLimiter, verifyJWT, validate(authSchemas.changePassword), changePassword);
router.post('/refresh-token', authRateLimiter, validate(authSchemas.refreshToken), refreshToken);
router.post('/forgot-password', authRateLimiter, validate(authSchemas.forgotPassword), forgotPassword);
router.post('/verify-otp', authRateLimiter, validate(authSchemas.verifyOtp), verifyOtp);
router.post('/reset-password', authRateLimiter, validate(authSchemas.resetPassword), resetPassword);

export default router;
