// Standard error shape thrown from controllers and caught by the global
// error handler in app.js. Carries an HTTP status code and optional details.

class ApiError extends Error {
  constructor(statusCode, message = 'Something went wrong', errors = [], stack = '') {
    super(message);
    this.statusCode = statusCode;
    this.data = null;
    this.success = false;
    this.errors = errors;
    // Marks an intentional, client-safe error (vs an unexpected/programmer one).
    // The global error handler forwards these messages; everything else is
    // replaced with a generic message.
    this.isOperational = true;

    if (stack) {
      this.stack = stack;
    } else {
      Error.captureStackTrace(this, this.constructor);
    }
  }
}

export { ApiError };
