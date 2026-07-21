// Call REST endpoints — a socket-independent control path for calls.
//
// Used when a killed/backgrounded callee declines from the native call screen
// and has no live socket to emit `call:reject` over. This mirrors the socket
// reject handler so the caller stops ringing immediately instead of waiting out
// the ring timeout.

import { ApiResponse } from '../utils/ApiResponse.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { getIO } from '../socket/index.js';
import { SOCKET_EVENTS } from '../constants.js';
import { getCallMeta, getCallMembers, reapCall } from '../services/redis.service.js';

// POST /api/v1/calls/:callId/reject — decline a ringing call over HTTP.
export const rejectCall = asyncHandler(async (req, res) => {
  const { callId } = req.params;
  const meta = await getCallMeta(callId);
  // Already gone (caller cancelled / call ended) — idempotent success.
  if (!meta) {
    return res.status(200).json(new ApiResponse(200, {}, 'Call already ended'));
  }

  const members = await getCallMembers(callId);
  const who = String(req.user._id);
  const io = getIO();
  for (const sid of Object.keys(members)) {
    io.to(sid).emit(SOCKET_EVENTS.CALL_REJECTED, { userId: who, callId });
  }
  // Only the caller is present (callee never accepted) → tear the session down,
  // which also clears the caller's in-call marker so they aren't left stuck.
  if (Object.keys(members).length <= 1) {
    await reapCall(callId, meta.channel, members);
  }

  return res.status(200).json(new ApiResponse(200, {}, 'Call rejected'));
});
