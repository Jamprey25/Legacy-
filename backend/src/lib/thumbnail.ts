// Server-side thumbnail generation (csam-thumbnail-generation).
//
// Fires post-clear (from the upload onUploadCompleted webhook) for IMAGE media only.
// Downscales to a small WebP for teaser cards (scan response / Memory Lane). sharp drops
// EXIF/metadata by default, so the thumbnail is also a privacy belt-and-braces.
//
// Phase 1: images only. Video thumbnails need a frame extract (ffmpeg) — out of scope;
// returns null so the caller leaves thumbnail_key null (teaser falls back gracefully).
//
// Best-effort: any failure returns null. Thumbnail generation must never block or revert
// scan_status — the original is already clear.

import { put } from "@vercel/blob";
import { blobPutAccess } from "./blobSignedGet.js";
import { fetchAllowedStorageUrl } from "./storageUrl.js";

// Lazy-loaded so a missing/broken native sharp binary cannot crash app startup.
// Only the image-processing path (post-upload webhook) ever loads it.
async function loadSharp() {
  const mod = await import("sharp");
  return mod.default;
}

const THUMB_MAX_WIDTH = 400; // px — enough for a teaser card, tiny payload
const THUMB_WEBP_QUALITY = 70;

/**
 * Pure resize step: image bytes → small WebP thumbnail bytes. Drops EXIF/metadata
 * (sharp default) and honors orientation. Extracted for unit testing without network.
 */
export async function resizeToThumbnail(input: Buffer): Promise<Buffer> {
  const sharp = await loadSharp();
  return sharp(input)
    .rotate() // honor EXIF orientation before metadata is dropped
    .resize({ width: THUMB_MAX_WIDTH, withoutEnlargement: true })
    .webp({ quality: THUMB_WEBP_QUALITY })
    .toBuffer();
}

/**
 * Generate a thumbnail from an uploaded image and store it in Vercel Blob.
 * @returns the thumbnail's public blob URL (used as thumbnail_key), or null if skipped/failed.
 */
export async function generateAndStoreThumbnail(
  sourceUrl: string,
  memoryId: string,
  contentType: string | undefined,
): Promise<string | null> {
  if (!contentType || !contentType.startsWith("image/")) {
    return null; // non-image (video/text) — no server thumbnail in Phase 1
  }

  try {
    const res = await fetchAllowedStorageUrl(sourceUrl);
    if (!res.ok) return null;
    const input = Buffer.from(await res.arrayBuffer());

    const thumb = await resizeToThumbnail(input);

    const blob = await put(`thumbnails/${memoryId}.webp`, thumb, {
      access: blobPutAccess(),
      addRandomSuffix: true,
      contentType: "image/webp",
    });

    return blob.url;
  } catch {
    // Best-effort — leave thumbnail_key null on any failure.
    return null;
  }
}
