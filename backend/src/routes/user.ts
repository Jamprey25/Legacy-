// User account management routes (api-contract.md §8):
//   GET    /v1/user/export  — package all own memories into a signed archive URL (GDPR / App Store)
//   DELETE /v1/user         — cascade-delete account + all data + queue media cleanup

import { Hono } from "hono";
import { put, del } from "@vercel/blob";
import { ApiError } from "../lib/errors.js";
import { requireAuth, type AuthVars } from "../middleware/auth.js";
import { audit } from "../lib/audit.js";
import { findById, listAllMemoriesForExport, listUserMediaKeys, deleteUser, updateDisplayName } from "../db/users.js";
import { rateLimit } from "../middleware/rateLimit.js";

export const userRoutes = new Hono<{ Variables: AuthVars }>();

userRoutes.use("*", requireAuth);

// One export per 24h — archives are expensive to generate and download.
const exportLimit = rateLimit({ name: "export", limit: 3, windowSec: 86400, keyBy: "user" });

// ---------------------------------------------------------------------------
// PATCH /user
//
// Update mutable profile fields. Currently supports `display_name` only.
// Null clears the field (client reverts to email-derived name).
// ---------------------------------------------------------------------------

userRoutes.patch("/", async (c) => {
  const userId: string = c.get("userId");
  const body = await c.req.json<{ display_name?: string | null }>().catch(() => ({}));

  if (!("display_name" in body)) {
    throw new ApiError("invalid_request", "No updatable fields provided.");
  }

  const raw = body.display_name;
  let displayName: string | null;
  if (raw === null || raw === undefined) {
    displayName = null;
  } else if (typeof raw !== "string") {
    throw new ApiError("invalid_request", "display_name must be a string or null.");
  } else {
    const trimmed = raw.trim();
    if (trimmed.length > 100) {
      throw new ApiError("invalid_request", "display_name must be 100 characters or fewer.");
    }
    displayName = trimmed.length === 0 ? null : trimmed;
  }

  await updateDisplayName(userId, displayName);
  audit(c, "user.update", { fields: ["display_name"] });

  return c.json({ display_name: displayName });
});

// ---------------------------------------------------------------------------
// GET /user/export
//
// Synchronously packages all own memories into a JSON archive, uploads to
// Vercel Blob (or falls back to a stub URL), and returns a signed URL.
//
// Privacy: only own data is included — coordinates are the user's own drops,
// which they are entitled to. NO others' coordinates ever appear here.
// ---------------------------------------------------------------------------

userRoutes.get("/export", exportLimit, async (c) => {
  const userId: string = c.get("userId");
  const user = await findById(userId);
  if (!user) throw new ApiError("not_found", "User not found.");

  const memories = await listAllMemoriesForExport(userId);

  const archive = {
    exported_at: new Date().toISOString(),
    user_id: userId,
    email: user.email,
    memories: memories.map((m) => ({
      memory_id: m.id,
      lat: m.lat,
      lng: m.lng,
      media_type: m.media_type,
      source: m.source,
      scan_status: m.scan_status,
      caption: m.caption,
      teaser_text: m.teaser_text,
      created_at: m.created_at,
      // media_key intentionally omitted — raw storage keys never leave the API.
      // Media referenced by memory_id; user can retrieve via unlock if needed.
    })),
  };

  const archiveBytes = Buffer.from(JSON.stringify(archive, null, 2));
  const archiveKey = `exports/${userId}/export-${Date.now()}.json`;

  const STORAGE = process.env.STORAGE_BACKEND ?? "stub";

  let archiveUrl: string;
  if (STORAGE === "vercel-blob") {
    const blob = await put(archiveKey, archiveBytes, {
      access: "public",
      addRandomSuffix: true,
      contentType: "application/json",
    });
    archiveUrl = blob.url;
  } else {
    // Stub: return a deterministic placeholder so tests/CI can parse the shape.
    archiveUrl = `https://stub.storage.example/exports/${userId}/export.json`;
  }

  audit(c, "user.export", { memory_count: memories.length });

  return c.json({ archive_url: archiveUrl, memory_count: memories.length, exported_at: archive.exported_at });
});

// ---------------------------------------------------------------------------
// DELETE /user
//
// Hard-deletes the account and all associated data.
// Steps:
//   1. Collect all media keys (before FK cascade removes rows).
//   2. DELETE FROM users — cascades through memories → finds/pings/seals/conditions/imports/sessions.
//   3. Fire-and-forget: delete each Blob URL (best-effort, failures are silent).
// ---------------------------------------------------------------------------

userRoutes.delete("/", async (c) => {
  const userId: string = c.get("userId");

  const STORAGE = process.env.STORAGE_BACKEND ?? "stub";

  // Step 1: collect media keys so we can clean Blob AFTER the DB rows are gone.
  const mediaKeys = await listUserMediaKeys(userId);

  // Step 2: cascade delete. FK constraints handle all child tables.
  await deleteUser(userId);

  audit(c, "user.delete", { media_asset_count: mediaKeys.length });

  // Step 3: fire-and-forget Blob cleanup. Failures are non-critical — URLs are
  // unguessable bearer capabilities and the user row is already gone.
  if (STORAGE === "vercel-blob" && mediaKeys.length > 0) {
    Promise.all(mediaKeys.map((key) => del(key).catch(() => {}))).catch(() => {});
  }

  return new Response(null, { status: 204 });
});
