// Upload controller.
//
//  - presigned-put / presigned-get: hand the client short-lived URLs so it can
//    upload/download ENCRYPTED blobs straight to/from R2. The server never sees
//    file content.
//  - avatar: profile pictures are NOT E2E encrypted, so they flow through
//    multer → R2 here.

import { randomUUID } from 'crypto';
import { ApiError } from '../utils/ApiError.js';
import { ApiResponse } from '../utils/ApiResponse.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { sniffImageType } from '../utils/fileType.js';
import {
  getPresignedPutUrl,
  getPresignedGetUrl,
  uploadAvatar,
} from '../services/r2.service.js';
import { User } from '../models/user.model.js';

// GET /api/v1/upload/presigned-put?blobName=...
// If no blobName is supplied we mint a fresh random one so the client never
// controls object keys directly.
export const getPresignedPut = asyncHandler(async (req, res) => {
  const blobName = req.query.blobName || `files/${randomUUID()}`;
  const url = await getPresignedPutUrl(blobName, 60);
  return res
    .status(200)
    .json(new ApiResponse(200, { url, blobName, expiresIn: 60 }));
});

// GET /api/v1/upload/presigned-get?blobName=...
export const getPresignedGet = asyncHandler(async (req, res) => {
  const { blobName } = req.query;
  if (!blobName) throw new ApiError(400, 'blobName is required');
  const url = await getPresignedGetUrl(blobName, 3600);
  return res
    .status(200)
    .json(new ApiResponse(200, { url, blobName, expiresIn: 3600 }));
});

// POST /api/v1/upload/avatar  (auth, multipart field "avatar")
export const uploadAvatarFile = asyncHandler(async (req, res) => {
  if (!req.file?.buffer) throw new ApiError(400, 'No avatar file uploaded');

  // Content validation: verify the ACTUAL bytes are an allowed raster image.
  // The declared MIME type and filename extension are both attacker-controlled
  // and ignored here; SVG / HTML / scripts are rejected by the sniffer.
  const type = sniffImageType(req.file.buffer);
  if (!type) {
    throw new ApiError(400, 'Unsupported image format — use PNG, JPEG, WebP, or GIF');
  }

  // The object key carries no user-controlled component, and we store it with
  // the SNIFFED content type so R2 can never serve it as anything executable.
  const key = `avatars/${req.user._id}-${Date.now()}.${type.ext}`;
  const url = await uploadAvatar(req.file.buffer, key, type.mime);

  req.user.avatar = url;
  await req.user.save();

  return res
    .status(200)
    .json(new ApiResponse(200, { avatar: url }, 'Avatar updated'));
});
