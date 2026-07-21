// Cloudflare R2 service (S3-compatible).
//
// The server issues presigned URLs so encrypted blobs move directly between the
// client and R2 — the server never sees file bytes (which are AES-GCM
// ciphertext anyway). Avatars are the one exception: they flow through multer
// and are uploaded here because they are not E2E encrypted.

import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
  DeleteObjectsCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

const BUCKET = process.env.R2_BUCKET;

// R2 speaks the S3 API. Region is irrelevant but required by the SDK.
const s3 = new S3Client({
  region: 'auto',
  endpoint: process.env.R2_ENDPOINT,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY,
    secretAccessKey: process.env.R2_SECRET_KEY,
  },
});

/**
 * Presigned PUT URL — a short-lived window for the client to upload one blob.
 * @param {string} blobName random object key
 * @param {number} expiresIn seconds (default 60)
 */
export const getPresignedPutUrl = (blobName, expiresIn = 60) =>
  getSignedUrl(
    s3,
    new PutObjectCommand({ Bucket: BUCKET, Key: blobName }),
    { expiresIn }
  );

/**
 * Presigned GET URL — a short-lived window for the client to download a blob.
 * @param {string} blobName object key
 * @param {number} expiresIn seconds (default 3600)
 */
export const getPresignedGetUrl = (blobName, expiresIn = 3600) =>
  getSignedUrl(
    s3,
    new GetObjectCommand({
      Bucket: BUCKET,
      Key: blobName,
      // Defence in depth: force the object to download as an opaque binary even
      // if a signed URL is opened directly in a browser, so a stored blob can
      // never be rendered or executed. Clients fetch blobs programmatically and
      // decrypt them, so this has no effect on normal use.
      ResponseContentType: 'application/octet-stream',
      ResponseContentDisposition: 'attachment',
    }),
    { expiresIn }
  );

/** Delete a single blob (e.g. when a file message is removed). */
export const deleteBlob = (blobName) =>
  s3.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: blobName }));

/**
 * Batch-delete every blob belonging to a room (on End Room / expiry).
 * @param {string[]} blobNames
 */
export const deleteBlobsByRoom = async (blobNames) => {
  if (!blobNames || blobNames.length === 0) return;
  // S3 DeleteObjects handles up to 1000 keys per call.
  const chunks = [];
  for (let i = 0; i < blobNames.length; i += 1000) {
    chunks.push(blobNames.slice(i, i + 1000));
  }
  await Promise.all(
    chunks.map((chunk) =>
      s3.send(
        new DeleteObjectsCommand({
          Bucket: BUCKET,
          Delete: { Objects: chunk.map((Key) => ({ Key })) },
        })
      )
    )
  );
};

/**
 * Upload a profile picture (not E2E encrypted) and return its public URL.
 * @param {Buffer} fileBuffer
 * @param {string} fileName object key, e.g. "avatars/<userId>.jpg"
 * @param {string} contentType mime type
 */
export const uploadAvatar = async (fileBuffer, fileName, contentType) => {
  await s3.send(
    new PutObjectCommand({
      Bucket: BUCKET,
      Key: fileName,
      Body: fileBuffer,
      ContentType: contentType,
    })
  );
  // Prefer a configured public/CDN domain; fall back to the raw endpoint.
  const base = process.env.R2_PUBLIC_URL || process.env.R2_ENDPOINT;
  return `${base.replace(/\/$/, '')}/${fileName}`;
};
