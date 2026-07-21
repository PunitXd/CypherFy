// Central error handling.
//
// Contract: clients NEVER see stack traces, internal file paths, raw database
// errors, or parser internals. They get a curated message (for errors we threw
// on purpose) or a generic one (for everything else). Full detail is always
// logged server-side for debugging. Registered last in app.js.

import { ApiError } from '../utils/ApiError.js';

// Log server-side. NEVER logs the request body (may hold ciphertext / tokens).
// Unexpected + 5xx errors log the full stack; expected 4xx get a concise line.
const logError = (err, req, statusCode, withStack) => {
  const where = `${req?.method || '-'} ${req?.originalUrl || '-'} -> ${statusCode}`;
  if (withStack) console.error(`[error] ${where}\n`, err?.stack || err);
  else console.warn(`[warn]  ${where}: ${err?.message || 'error'}`);
};

// Map known framework/library errors to a SAFE status + generic message. Their
// raw messages can carry file paths, DB index/collection names, offending
// values, or parser internals — so we never forward them.
const mapKnownError = (err) => {
  if (!err) return null;
  // body-parser (express.json)
  if (err.type === 'entity.parse.failed') return { statusCode: 400, message: 'Malformed request body' };
  if (err.type === 'entity.too.large') return { statusCode: 413, message: 'Request payload too large' };
  // Mongoose
  if (err.name === 'ValidationError') return { statusCode: 400, message: 'Invalid input' };
  if (err.name === 'CastError') return { statusCode: 400, message: 'Invalid identifier' };
  // MongoDB duplicate key — the raw message leaks the index + offending value.
  if (err.code === 11000) return { statusCode: 409, message: 'That value is already in use' };
  // jsonwebtoken (normally caught in middleware, but be defensive)
  if (err.name === 'JsonWebTokenError' || err.name === 'TokenExpiredError') return { statusCode: 401, message: 'Unauthorized' };
  // multer (file upload)
  if (err.name === 'MulterError') {
    return { statusCode: 400, message: err.code === 'LIMIT_FILE_SIZE' ? 'File too large' : 'File upload failed' };
  }
  return null;
};

// Clean JSON 404 for unmatched routes (Express's default echoes method + path).
export const notFoundHandler = (_req, res) => {
  res.status(404).json({ success: false, message: 'Resource not found', errors: [] });
};

// eslint-disable-next-line no-unused-vars
export const errorHandler = (err, req, res, _next) => {
  // 1) Errors we threw on purpose — messages are curated and client-safe.
  if (err instanceof ApiError) {
    logError(err, req, err.statusCode, err.statusCode >= 500);
    return res.status(err.statusCode).json({
      success: false,
      message: err.message,
      errors: Array.isArray(err.errors) ? err.errors : [],
    });
  }

  // 2) Recognised library errors — mapped to a safe, generic message.
  const mapped = mapKnownError(err);
  if (mapped) {
    logError(err, req, mapped.statusCode, mapped.statusCode >= 500);
    return res.status(mapped.statusCode).json({ success: false, message: mapped.message, errors: [] });
  }

  // 3) Anything else is unexpected: log FULL detail, return a generic 500 with
  //    nothing internal in it.
  logError(err, req, 500, true);
  return res.status(500).json({ success: false, message: 'Internal Server Error', errors: [] });
};
