// Rate limiting — endpoint-appropriate tiers, all thresholds env-configurable
// via the RATE_LIMIT block in constants.js (see .env.example).
//
//  - authRateLimiter : STRICT. Auth routes (login/register/reset/OTP/refresh).
//                      Per-IP AND per-account, Redis-backed EXPONENTIAL BACKOFF
//                      (not a hard lockout). Distributed-correct across instances.
//  - publicLimiter   : MODERATE. Public endpoints (guest room create/validate,
//                      presigned upload URLs). Per-IP fixed window.
//  - userLimiter     : LOOSE. Authenticated user actions. Per-account (user id).
//  - apiLimiter      : Very loose global safety net mounted on all of /api.
//
// The IP-tier limiters use express-rate-limit's in-memory store (per instance);
// the auth tier uses Redis so backoff is shared across a horizontally-scaled
// deployment where credential-stuffing protection matters most.

import rateLimit from 'express-rate-limit';
import { RATE_LIMIT } from '../constants.js';
import { registerAuthAttempt } from '../services/redis.service.js';

// ---- Strict auth tier: per-IP + per-account exponential backoff ----------

const lowerEmail = (req) => {
  const e = req.body?.email;
  return typeof e === 'string' && e.trim() ? e.trim().toLowerCase() : null;
};

export const authRateLimiter = async (req, res, next) => {
  if (!RATE_LIMIT.ENABLED) return next();
  const cfg = RATE_LIMIT.AUTH;

  try {
    const checks = [
      registerAuthAttempt('ip', req.ip, {
        freeAttempts: cfg.IP_FREE_ATTEMPTS,
        backoffBaseMs: cfg.BACKOFF_BASE_MS,
        backoffMaxMs: cfg.BACKOFF_MAX_MS,
        decayMs: cfg.DECAY_MS,
      }),
    ];

    // Per-account limit only applies when the request identifies an account.
    const email = lowerEmail(req);
    if (email) {
      checks.push(
        registerAuthAttempt('account', email, {
          freeAttempts: cfg.ACCOUNT_FREE_ATTEMPTS,
          backoffBaseMs: cfg.BACKOFF_BASE_MS,
          backoffMaxMs: cfg.BACKOFF_MAX_MS,
          decayMs: cfg.DECAY_MS,
        })
      );
    }

    const results = await Promise.all(checks);
    const blocked = results.filter((r) => r.limited);
    if (blocked.length) {
      const retryAfterSec = Math.max(...blocked.map((r) => r.retryAfterSec));
      res.set('Retry-After', String(retryAfterSec));
      return res.status(429).json({
        success: false,
        message: `Too many attempts. Please try again in ${retryAfterSec}s.`,
        retryAfter: retryAfterSec,
      });
    }
    return next();
  } catch (err) {
    // Fail OPEN — a Redis hiccup must never lock users out of authentication.
    console.error('authRateLimiter error (failing open):', err.message);
    return next();
  }
};

// ---- express-rate-limit tiers (fixed window, per-IP or per-user) ----------

const buildLimiter = ({ windowMs, max, message, keyGenerator }) =>
  rateLimit({
    windowMs,
    limit: max,
    standardHeaders: true,
    legacyHeaders: false,
    // One master switch disables every tier (e.g. for tests).
    skip: () => !RATE_LIMIT.ENABLED,
    ...(keyGenerator ? { keyGenerator } : {}),
    message: { success: false, message },
  });

// Moderate — public endpoints, keyed by IP (default key generator).
export const publicLimiter = buildLimiter({
  windowMs: RATE_LIMIT.PUBLIC.WINDOW_MS,
  max: RATE_LIMIT.PUBLIC.MAX,
  message: 'Too many requests, please slow down.',
});

// Loose — authenticated actions. Mounted AFTER verifyJWT, so req.user is always
// present; key by user id so one account's traffic never throttles another's.
export const userLimiter = buildLimiter({
  windowMs: RATE_LIMIT.USER.WINDOW_MS,
  max: RATE_LIMIT.USER.MAX,
  message: 'Too many requests, please slow down.',
  keyGenerator: (req) => `u:${req.user?._id ?? req.ip}`,
});

// Very loose global safety net across the whole API (keyed by IP).
export const apiLimiter = buildLimiter({
  windowMs: RATE_LIMIT.GLOBAL.WINDOW_MS,
  max: RATE_LIMIT.GLOBAL.MAX,
  message: 'Too many requests, please slow down.',
});
