// Schema validation — reject (never sanitize) any input that doesn't match.
//
// HTTP:  validate({ body?, query?, params? }) parses each part with its zod
//        schema. On failure it forwards a 400 ApiError carrying the field-level
//        issues; on success it REPLACES req.body/query/params with the parsed
//        (and coerced/normalized) values so handlers get well-typed input.
//
// Socket: validatePayload(schema, payload) returns { ok, data } or { ok:false,
//         error } so a handler can bail and emit an error on a bad payload.

import { ApiError } from '../utils/ApiError.js';

// Flatten a ZodError into [{ field, message }]. The empty path (e.g. an
// unknown-key or failed object refinement) is reported against the part name.
const formatIssues = (error, part) =>
  error.issues.map((i) => ({
    field: i.path.length ? i.path.join('.') : part,
    message: i.message,
  }));

export const validate = (schemas) => (req, _res, next) => {
  for (const part of ['params', 'query', 'body']) {
    const schema = schemas[part];
    if (!schema) continue;
    const result = schema.safeParse(req[part]);
    if (!result.success) {
      return next(new ApiError(400, 'Validation failed', formatIssues(result.error, part)));
    }
    // Express 4: req.params/query/body are writable — swap in the parsed values.
    req[part] = result.data;
  }
  return next();
};

// Validate a socket event payload. Missing payloads are treated as {} so
// schemas made entirely of optional fields still accept an empty emit.
export const validatePayload = (schema, payload) => {
  const result = schema.safeParse(payload ?? {});
  if (result.success) return { ok: true, data: result.data };
  return { ok: false, error: formatIssues(result.error, 'payload') };
};
