// Content-based image type detection by magic bytes. We validate the ACTUAL
// file bytes — never the client-declared MIME type or the filename extension,
// both of which are trivially forged. Only raster image formats are accepted;
// SVG is intentionally unsupported because it can carry executable script.

const startsWith = (buf, bytes, offset = 0) =>
  bytes.every((b, i) => buf[offset + i] === b);

/**
 * @param {Buffer} buf
 * @returns {{mime: string, ext: string} | null} null = not an allowed raster image
 */
export const sniffImageType = (buf) => {
  if (!Buffer.isBuffer(buf) || buf.length < 12) return null;

  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (startsWith(buf, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
    return { mime: 'image/png', ext: 'png' };
  // JPEG: FF D8 FF
  if (startsWith(buf, [0xff, 0xd8, 0xff])) return { mime: 'image/jpeg', ext: 'jpg' };
  // GIF: "GIF8"
  if (startsWith(buf, [0x47, 0x49, 0x46, 0x38])) return { mime: 'image/gif', ext: 'gif' };
  // WEBP: "RIFF" .... "WEBP"
  if (startsWith(buf, [0x52, 0x49, 0x46, 0x46]) && startsWith(buf, [0x57, 0x45, 0x42, 0x50], 8))
    return { mime: 'image/webp', ext: 'webp' };

  return null; // SVG, HTML, scripts, or anything else → rejected
};
