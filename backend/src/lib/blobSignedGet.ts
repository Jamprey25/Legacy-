// Vercel Blob signed GET URLs + access mode (SEC-P3-1, SEC-P3-2).
//
// New uploads use `access: 'private'` when BLOB_ACCESS=private (default for vercel-blob).
// Legacy public blob URLs in the DB still resolve via presign with access: 'public'.

import { issueSignedToken, presignUrl } from "@vercel/blob";

export const EXPORT_GET_TTL_SECONDS = 15 * 60; // GDPR export link lifetime
export const MEDIA_GET_TTL_SECONDS = 60 * 60; // unlock / owner media view window

/** Default private for Vercel Blob unless explicitly overridden. */
export function blobPutAccess(): "public" | "private" {
  const mode = process.env.BLOB_ACCESS ?? "private";
  return mode === "public" ? "public" : "private";
}

/** Infer access mode from a stored blob URL (legacy public vs new private). */
export function blobAccessForKey(mediaKey: string): "public" | "private" {
  if (mediaKey.includes(".private.blob.vercel-storage.com")) return "private";
  if (blobPutAccess() === "private" && !mediaKey.startsWith("http")) {
    return "private";
  }
  return "public";
}

/** Extract blob pathname from a full URL or return path-like keys as-is. */
export function blobPathnameFromKey(mediaKey: string): string {
  if (!mediaKey.startsWith("http")) {
    return mediaKey.startsWith("/") ? mediaKey.slice(1) : mediaKey;
  }
  const parsed = new URL(mediaKey);
  const path = parsed.pathname.startsWith("/") ? parsed.pathname.slice(1) : parsed.pathname;
  return decodeURIComponent(path);
}

export function isVercelBlobKey(mediaKey: string): boolean {
  if (!mediaKey.startsWith("http")) return false;
  try {
    return new URL(mediaKey).hostname.includes("blob.vercel-storage.com");
  } catch {
    return false;
  }
}

/**
 * Mint a time-limited GET URL for a Vercel Blob object.
 * Falls back to the raw URL for non-blob keys (stub/S3 placeholder).
 */
export async function signedVercelBlobGetUrl(
  mediaKey: string,
  ttlSeconds: number,
): Promise<{ url: string; expiresAt: string }> {
  const expiresAt = new Date(Date.now() + ttlSeconds * 1000).toISOString();

  if (!isVercelBlobKey(mediaKey)) {
    return { url: mediaKey, expiresAt };
  }

  const pathname = blobPathnameFromKey(mediaKey);
  const access = blobAccessForKey(mediaKey);
  const delegationValidUntil = Date.now() + Math.max(ttlSeconds, 60) * 1000;

  const token = await issueSignedToken({
    pathname,
    operations: ["get"],
    validUntil: delegationValidUntil,
  });

  const { presignedUrl } = await presignUrl(token, {
    pathname,
    operation: "get",
    access,
    validUntil: Date.now() + ttlSeconds * 1000,
  });

  return { url: presignedUrl, expiresAt };
}
