// Wraps an async Express handler so thrown errors are forwarded to next()
// instead of leaving a promise rejection unhandled. Every controller uses this.

const asyncHandler = (requestHandler) => async (req, res, next) => {
  try {
    await requestHandler(req, res, next);
  } catch (error) {
    next(error);
  }
};

export { asyncHandler };
