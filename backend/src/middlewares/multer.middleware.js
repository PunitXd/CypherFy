// Multer middleware — buffers an uploaded avatar IN MEMORY before the upload
// controller streams it to R2. Only used for profile pictures; E2E-encrypted
// chat files never touch the server (presigned PUT instead).
//
// Memory storage (not disk) is deliberate: nothing is ever written to the
// filesystem, so an upload can never land in the web root, and there is no
// temp-file cleanup window to leak through. The authoritative type check is
// magic-byte sniffing in the controller; this filter is only a cheap first pass
// on the declared type (SVG is explicitly barred — it can carry script).

import multer from 'multer';
import { FILE } from '../constants.js';

const fileFilter = (_req, file, cb) => {
  const ok =
    typeof file.mimetype === 'string' &&
    file.mimetype.startsWith('image/') &&
    file.mimetype !== 'image/svg+xml';
  cb(ok ? null : new Error('Only raster image files are allowed'), ok);
};

export const upload = multer({
  storage: multer.memoryStorage(),
  fileFilter,
  limits: { fileSize: FILE.AVATAR_MAX_MB * 1024 * 1024, files: 1 },
});
