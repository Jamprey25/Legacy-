// Internal storage webhook — called by the upload pipeline when an asset lands.
//
// In dev/staging (CSAM_PIPELINE=stub, non-production): flips scan_status to 'clear'.
// In production with stub pipeline: rejects — content must not auto-clear (SEC-P2-1).
//
// Security: all requests must include X-Webhook-Secret matching WEBHOOK_SECRET.
// media_key is validated against an HTTPS storage allowlist before any fetch (SEC-P2-2).

import { Hono } from "hono";
import { ApiError } from "../lib/errors.js";
import { assertScanClearAllowed, csamPipelineMode, isDevStubPipeline } from "../lib/csamPipeline.js";
import {
  assertAllowedStorageUrl,
  assertMediaKeyBelongsToMemory,
} from "../lib/storageUrl.js";
import { getMemoryById, updateMemoryAfterUpload, setThumbnailKey } from "../db/memories.js";
import { generateAndStoreThumbnail } from "../lib/thumbnail.js";
import { stripAndReplaceBlob } from "../lib/exif.js";
import type { AuthVars } from "../middleware/auth.js";

export const webhookRoutes = new Hono<{ Variables: AuthVars }>();

const WEBHOOK_SECRET = process.env.WEBHOOK_SECRET ?? "";

// ---------------------------------------------------------------------------
// POST /internal/webhook/storage
//
// Body: { memory_id: string, media_key: string }
// Header: X-Webhook-Secret: <WEBHOOK_SECRET>
//
// On success: 200 { memory_id, scan_status: "clear" }
// ---------------------------------------------------------------------------

webhookRoutes.post("/storage", async (c) => {
  const incomingSecret = c.req.header("X-Webhook-Secret") ?? "";
  if (!WEBHOOK_SECRET || incomingSecret !== WEBHOOK_SECRET) {
    throw new ApiError("unauthorized", "Invalid webhook secret.");
  }

  const body = (await c.req.json().catch(() => null)) as {
    memory_id: unknown;
    media_key: unknown;
  } | null;
  if (!body) throw new ApiError("invalid_request", "Request body must be JSON.");

  const { memory_id, media_key } = body;
  if (typeof memory_id !== "string" || !memory_id) {
    throw new ApiError("invalid_request", "memory_id is required.");
  }
  if (typeof media_key !== "string" || !media_key) {
    throw new ApiError("invalid_request", "media_key is required.");
  }

  const memory = await getMemoryById(memory_id);
  if (!memory) throw new ApiError("not_found", "Memory not found.");

  assertAllowedStorageUrl(media_key);
  assertMediaKeyBelongsToMemory(media_key, memory_id);

  if (isDevStubPipeline()) {
    const contentType = c.req.header("Content-Type-Upload") ?? undefined;

    let cleanKey = media_key;
    if (process.env.STORAGE_BACKEND === "vercel-blob") {
      const stripped = await stripAndReplaceBlob(media_key, memory_id, contentType);
      if (stripped) cleanKey = stripped;
    }

    assertScanClearAllowed();
    const updated = await updateMemoryAfterUpload(memory_id, cleanKey);
    if (!updated) throw new ApiError("not_found", "Memory not found.");

    if (process.env.STORAGE_BACKEND === "vercel-blob") {
      generateAndStoreThumbnail(cleanKey, memory_id, contentType)
        .then((thumbKey) => {
          if (thumbKey) return setThumbnailKey(memory_id, thumbKey);
        })
        .catch(() => {});
    }

    return c.json({ memory_id, scan_status: "clear" });
  }

  if (csamPipelineMode() === "stub") {
    throw new ApiError("internal_error", "Content scanning is not configured.");
  }

  throw new ApiError("internal_error", "Production CSAM pipeline not yet wired.");
});
