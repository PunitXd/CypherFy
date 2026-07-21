// JWT auth middleware. Verifies the access token, loads the user, and attaches
// it to req.user. Tokens are accepted from the Authorization: Bearer header or
// an httpOnly `accessToken` cookie.

import jwt from 'jsonwebtoken';
import { User } from '../models/user.model.js';
import { ApiError } from '../utils/ApiError.js';
import { asyncHandler } from '../utils/asyncHandler.js';

export const verifyJWT = asyncHandler(async (req, _res, next) => {
  const token =
    req.cookies?.accessToken ||
    req.header('Authorization')?.replace('Bearer ', '');

  if (!token) {
    throw new ApiError(401, 'Unauthorized — no access token provided');
  }

  let decoded;
  try {
    decoded = jwt.verify(token, process.env.ACCESS_TOKEN_SECRET);
  } catch {
    throw new ApiError(401, 'Unauthorized — invalid or expired access token');
  }

  // Never send passwordHash / tokens downstream.
  const user = await User.findById(decoded._id).select(
    '-passwordHash -refreshTokens'
  );
  if (!user) {
    throw new ApiError(401, 'Unauthorized — user no longer exists');
  }

  // Token minted before the last password change → force re-login. This is what
  // makes a password change/reset log out other sessions immediately, without
  // waiting for the access token to expire.
  if (user.changedPasswordAfter(decoded.iat)) {
    throw new ApiError(401, 'Unauthorized — password changed, please log in again');
  }

  req.user = user;
  next();
});

// Like verifyJWT but never rejects: attaches req.user when a valid token is
// present, otherwise continues as a guest. For routes that work for everyone but
// want to know the caller when they're signed in (e.g. ephemeral room creation).
export const optionalAuth = asyncHandler(async (req, _res, next) => {
  const token =
    req.cookies?.accessToken ||
    req.header('Authorization')?.replace('Bearer ', '');
  if (!token) return next();
  try {
    const decoded = jwt.verify(token, process.env.ACCESS_TOKEN_SECRET);
    const user = await User.findById(decoded._id).select(
      '-passwordHash -refreshTokens'
    );
    if (user && !user.changedPasswordAfter(decoded.iat)) req.user = user;
  } catch {
    // Invalid/expired token → treat as a guest.
  }
  next();
});
