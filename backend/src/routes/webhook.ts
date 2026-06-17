// Internal storage webhook — called by the upload pipeline when an asset lands.
//
// In dev/staging (CSAM_PIPELINE=stub or unset): immediately flips scan_status
// to 'clear' so the memory is discoverable. In production this route will be
// replaced by the real CSAM hash-match + EXIF-strip pipeline.
//
// Security: all requests must include X-Webhook-Secret matching WEBHOOK_SECRET.
// This header is set by the storage provider (or the iOS background upload client
// in stub mode). Never expose this route without the secret check.
//
// Server-side EXIF strip happens here too (stub: no-op until csam-server-exif-strip
// task is implemented — client already strips before upload per ios-exif-strip).

import { Hono } from "hono";
import { ApiError } from "../lib/errors.js";
import { updateMemoryAfterUpload } from "../db/memories.js";
import type { AuthVars } from "../middleware/auth.js";

export const webhookRoutes = new Hono<{ Variables: AuthVars }>();

const PIPELINE_MODE = process.env.CSAM_PIPELINE ?? "stub";
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
  // Secret check — enforced in all environments.
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

  if (PIPELINE_MODE === "stub") {
    // Stub: no CSAM scan, no real EXIF strip — just mark clear.
    // csam-server-exif-strip task will add real metadata removal here.
    const updated = await updateMemoryAfterUpload(memory_id, media_key);
    if (!updated) throw new ApiError("not_found", "Memory not found.");

    return c.json({ memory_id, scan_status: "clear" });
  }

  // Production path (csam-vendor-live task): real hash-match + reporting.
  throw new ApiError("internal_error", "Production CSAM pipeline not yet wired.");
});
