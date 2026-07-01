// Server-side EXIF strip (csam-server-exif-strip).
//
// Belt-and-braces metadata removal that fires in the upload webhook after a
// successful client upload. The client already strips before upload (ios-exif-strip),
// this is the server-side guarantee of the guarantee.
//
// Uses sharp, which strips all EXIF/IPTC/XMP/ICC by default when re-encoding.
// We re-encode as JPEG (for photos) or the detected format to stay lossless-ish
// while guaranteeing no metadata survives. For non-image types (video) we pass
// through — video EXIF strip is out of scope for Phase 1.
//
// Best-effort: returns null on failure so the caller falls back to the original.
// SEC-MED-4.

import { put, del } from "@vercel/blob";
import { fetchAllowedStorageUrl } from "./storageUrl.js";

// Lazy-loaded so a missing/broken native sharp binary cannot crash app startup.
// Only the upload webhook path ever loads it.
async function loadSharp() {
  const mod = await import("sharp");
  return mod.default;
}

/**
 * Pure strip step: image bytes → re-encoded bytes with all metadata removed.
 * Extracted for unit testing without network I/O.
 */
export async function stripImageMetadata(input: Buffer): Promise<Buffer> {
  const sharp = await loadSharp();
  // keepMetadata(false) is sharp's default; explicit here for documentation.
  // rotate() auto-corrects orientation so the visual result is unchanged.
  const meta = await sharp(input).metadata();
  const format = meta.format ?? "jpeg";

  // sharp strips all metadata by default (EXIF/IPTC/XMP/ICC) when re-encoding.
  // rotate() auto-corrects orientation from EXIF before the metadata is dropped,
  // so the visual result is unchanged but no GPS/timestamp data survives.
  const pipeline = sharp(input).rotate();

  if (format === "png") return pipeline.png().toBuffer();
  if (format === "webp") return pipeline.webp().toBuffer();
  // Default: JPEG (covers jpg, heif, tiff, etc.)
  return pipeline.jpeg({ quality: 95 }).toBuffer();
}

/**
 * Download the asset at blobUrl, strip EXIF, re-upload in place.
 * Returns the (possibly new) clean URL, or null if skipped / failed.
 *
 * For Vercel Blob: uploads the clean copy with addRandomSuffix to get a new
 * unguessable URL, then deletes the original. Returns the new URL so the
 * caller can update media_key in the DB.
 *
 * For non-image content-types: returns the original URL unchanged (pass-through).
 */
export async function stripAndReplaceBlob(
  blobUrl: string,
  memoryId: string,
  contentType: string | undefined,
): Promise<string | null> {
  if (!contentType || !contentType.startsWith("image/")) {
    return blobUrl; // video / text — pass through
  }

  try {
    const res = await fetchAllowedStorageUrl(blobUrl);
    if (!res.ok) return null;
    const original = Buffer.from(await res.arrayBuffer());

    const clean = await stripImageMetadata(original);

    // Re-upload the clean bytes.
    const ext = contentType.includes("png") ? "png" : contentType.includes("webp") ? "webp" : "jpg";
    const blob = await put(`memories/${memoryId}/original.${ext}`, clean, {
      access: "public",
      addRandomSuffix: true,
      contentType: contentType.startsWith("image/png") ? "image/png"
        : contentType.startsWith("image/webp") ? "image/webp"
        : "image/jpeg",
    });

    // Best-effort delete the original (old URL is unguessable, so not urgent).
    del(blobUrl).catch(() => {});

    return blob.url;
  } catch {
    // Never block scan_status on strip failure — original is already stored.
    return null;
  }
}
