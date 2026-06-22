// Vercel Blob client-upload token endpoint (storage decision: Vercel Blob now,
// S3 later — q-storage-backend, Joseph 2026-06-17).
//
// Flow (api-contract §3.2):
//   1. iOS calls POST /v1/memories → gets memory_id (scan_status: pending).
//   2. iOS performs the Vercel Blob client-upload handshake against POST /v1/uploads:
//        a. POST { type: "blob.generate-client-token", payload: { pathname, callbackUrl,
//           clientPayload, multipart, contentType } } — clientPayload carries the memory_id.
//        b. Receives { type, clientToken }.
//        c. PUTs the (EXIF-stripped) bytes directly to Vercel Blob using clientToken.
//   3. Vercel calls onUploadCompleted → we flip scan_status → clear and store blob.url.
//
// handleUpload() drives a+b and verifies the onUploadCompleted webhook signature, so we
// never trust the client for the completion event.
//
// PRIVACY TRADE-OFF (Phase 1): blobs are uploaded `access: "public"` with
// addRandomSuffix → the URL is an unguessable bearer capability. This is NOT a
// short-TTL signed URL; a leaked URL stays valid. Acceptable for Phase 1 private-tier
// memories; MUST revisit before public-tier / Phase 3 (see architecture-decisions DEC-23).
//
// onUploadCompleted does NOT fire on localhost (Vercel can't reach it). Dev uses the
// existing POST /internal/webhook/storage stub to flip scan_status instead.

import { Hono } from "hono";
import { handleUpload, type HandleUploadBody } from "@vercel/blob/client";
import { put } from "@vercel/blob";
import { ApiError } from "../lib/errors.js";
import { getMemoryByOwner, updateMemoryAfterUpload, setThumbnailKey } from "../db/memories.js";
import { setMediaAfterUpload, setMediaThumbnail } from "../db/memoryMedia.js";
import { generateAndStoreThumbnail } from "../lib/thumbnail.js";
import { requireAuth, type AuthVars } from "../middleware/auth.js";
import { rateLimit } from "../middleware/rateLimit.js";
import { audit } from "../lib/audit.js";

export const uploadsRoutes = new Hono<{ Variables: AuthVars }>();

uploadsRoutes.use("*", requireAuth);
// A memory holds many photos, so uploads are no longer 1:1 with memory creates — an import
// of several multi-photo visits can push hundreds of blobs. Generous per-user/hour budget;
// the real fix for very large imports is the background uploader (BackgroundMediaUploader),
// tracked as a follow-up. Until then this ceiling keeps "upload all photos" workable.
uploadsRoutes.use("*", rateLimit({ name: "upload", limit: 500, windowSec: 3600, keyBy: "user" }));

const ALLOWED_CONTENT_TYPES = ["image/jpeg", "image/png", "image/webp", "video/mp4"];
const MAX_UPLOAD_BYTES = 25 * 1024 * 1024; // 25 MB — generous for a phone photo/short clip

function extFor(contentType: string): string {
  if (contentType.includes("png")) return "png";
  if (contentType.includes("webp")) return "webp";
  if (contentType.includes("mp4")) return "mp4";
  return "jpg";
}

// Server-side upload: the client POSTs the (already EXIF-stripped) bytes here and we
// store them with the official @vercel/blob `put()`. This replaces the fragile
// client-side reverse-engineering of Vercel's internal blob upload protocol.
// Body: raw binary. Headers: Content-Type (asset type), X-Memory-Id.
uploadsRoutes.post("/direct", async (c) => {
  const userId: string = c.get("userId");
  const memoryId = c.req.header("x-memory-id");
  const contentType = c.req.header("content-type") ?? "application/octet-stream";

  // Which photo of the memory this is. Absent/0 = hero (mirrored onto memories.media_key);
  // 1+ = additional photos that live only in memory_media.
  const positionRaw = c.req.header("x-media-position");
  const position = positionRaw ? Number.parseInt(positionRaw, 10) : 0;

  if (!memoryId) throw new ApiError("invalid_request", "X-Memory-Id header is required.");
  if (!ALLOWED_CONTENT_TYPES.includes(contentType)) {
    throw new ApiError("invalid_request", `Unsupported content type: ${contentType}`);
  }
  if (!Number.isInteger(position) || position < 0) {
    throw new ApiError("invalid_request", "X-Media-Position must be a non-negative integer.");
  }

  // Authorize: memory must exist and belong to the requesting user.
  const memory = await getMemoryByOwner(memoryId, userId);
  if (!memory) throw new ApiError("not_found", "Memory not found.");

  const body = Buffer.from(await c.req.arrayBuffer());
  if (body.byteLength === 0) throw new ApiError("invalid_request", "Empty upload body.");
  if (body.byteLength > MAX_UPLOAD_BYTES) throw new ApiError("invalid_request", "File too large.");

  const mediaType = contentType.includes("mp4") ? "video" : "photo";
  const pathname = `memories/${memoryId}/${position}.${extFor(contentType)}`;
  const blob = await put(pathname, body, {
    access: "public",
    addRandomSuffix: true,
    contentType,
  });

  // Record this photo in the media set. Position 0 is also mirrored onto the memory row
  // (media_key + scan_status → clear) so discovery/proximity keep working off the hero.
  await setMediaAfterUpload(memoryId, position, blob.url, mediaType);
  if (position === 0) {
    await updateMemoryAfterUpload(memoryId, blob.url);
  }

  // Best-effort teaser thumbnail (images only; never blocks — sharp may be unavailable).
  const thumbnailKey = await generateAndStoreThumbnail(blob.url, memoryId, contentType);
  if (thumbnailKey) {
    await setMediaThumbnail(memoryId, position, thumbnailKey);
    if (position === 0) await setThumbnailKey(memoryId, thumbnailKey);
  }

  audit(c, "memory.upload_direct", { position });
  return c.json({ url: blob.url });
});

uploadsRoutes.post("/", async (c) => {
  const userId: string = c.get("userId");
  const body = (await c.req.json().catch(() => null)) as HandleUploadBody | null;
  if (!body) throw new ApiError("invalid_request", "Request body must be JSON.");

  const jsonResponse = await handleUpload({
    body,
    request: c.req.raw,
    onBeforeGenerateToken: async (_pathname, clientPayload) => {
      // clientPayload is a JSON string the iOS client sends: { memory_id }.
      let memoryId: string | undefined;
      if (clientPayload) {
        try {
          memoryId = (JSON.parse(clientPayload) as { memory_id?: string }).memory_id;
        } catch {
          throw new ApiError("invalid_request", "clientPayload must be JSON with memory_id.");
        }
      }
      if (!memoryId) throw new ApiError("invalid_request", "memory_id is required in clientPayload.");

      // Authorize: the memory must exist and belong to the requesting user.
      const memory = await getMemoryByOwner(memoryId, userId);
      if (!memory) throw new ApiError("not_found", "Memory not found.");

      return {
        allowedContentTypes: ALLOWED_CONTENT_TYPES,
        addRandomSuffix: true,
        // Carried through to onUploadCompleted (signed by Vercel, not client-trusted).
        tokenPayload: JSON.stringify({ userId, memoryId }),
      };
    },
    onUploadCompleted: async ({ blob, tokenPayload }) => {
      if (!tokenPayload) return;
      const { memoryId } = JSON.parse(tokenPayload) as { memoryId: string };
      // Store the full public blob URL as media_key and flip scan_status → clear.
      // (CSAM pipeline is a separate gate; in prod this is where the real scan hooks in.)
      await updateMemoryAfterUpload(memoryId, blob.url);

      // Post-clear: generate a teaser thumbnail (images only, best-effort — never blocks).
      const thumbnailKey = await generateAndStoreThumbnail(blob.url, memoryId, blob.contentType);
      if (thumbnailKey) await setThumbnailKey(memoryId, thumbnailKey);
    },
  });

  audit(c, "memory.upload_token", {});
  return c.json(jsonResponse);
});
