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
import { ApiError } from "../lib/errors.js";
import { getMemoryByOwner, updateMemoryAfterUpload, setThumbnailKey } from "../db/memories.js";
import { generateAndStoreThumbnail } from "../lib/thumbnail.js";
import { requireAuth, type AuthVars } from "../middleware/auth.js";
import { rateLimit } from "../middleware/rateLimit.js";
import { audit } from "../lib/audit.js";

export const uploadsRoutes = new Hono<{ Variables: AuthVars }>();

uploadsRoutes.use("*", requireAuth);
// Same budget as drops — uploads are 1:1 with memory creates.
uploadsRoutes.use("*", rateLimit({ name: "upload", limit: 20, windowSec: 3600, keyBy: "user" }));

const ALLOWED_CONTENT_TYPES = ["image/jpeg", "image/png", "image/webp", "video/mp4"];

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
