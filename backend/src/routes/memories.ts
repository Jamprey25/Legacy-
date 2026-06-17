// Memory routes (api-contract.md §3):
//   POST /v1/memories — drop a memory, get back memory_id + signed PUT URL
//   GET  /v1/memories/:id — fetch own memory detail (owner only)

import { Hono } from "hono";
import { ApiError } from "../lib/errors.js";
import { encode as geohashEncode } from "../lib/geohash.js";
import { generateSignedPutUrl } from "../lib/storage.js";
import { createMemory, getMemoryByOwner } from "../db/memories.js";
import { requireAuth, type AuthVars } from "../middleware/auth.js";

export const memoriesRoutes = new Hono<{ Variables: AuthVars }>();

memoriesRoutes.use("*", requireAuth);

// ---------------------------------------------------------------------------
// POST /memories
// ---------------------------------------------------------------------------

interface PostMemoriesBody {
  lat: unknown;
  lng: unknown;
  accuracy_m: unknown;
  media_type: unknown;
}

const VALID_MEDIA_TYPES = ["photo", "video", "text"] as const;
type MediaType = (typeof VALID_MEDIA_TYPES)[number];

/** Cooldown window after a live drop (seconds). Tunable in DB config table later. */
const COOLDOWN_SECONDS = 24 * 60 * 60; // 24 hours default

memoriesRoutes.post("/", async (c) => {
  const body = (await c.req.json().catch(() => null)) as PostMemoriesBody | null;
  if (!body) throw new ApiError("invalid_request", "Request body must be JSON.");

  const { lat, lng, accuracy_m, media_type } = body;

  // --- input validation ---
  if (typeof lat !== "number" || typeof lng !== "number") {
    throw new ApiError("invalid_coordinates", "lat and lng must be numbers.");
  }
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    throw new ApiError("invalid_coordinates", "Coordinates out of range.");
  }
  if (typeof accuracy_m !== "number" || accuracy_m <= 0 || accuracy_m > 1000) {
    throw new ApiError("invalid_request", "accuracy_m must be a number between 0 and 1000.");
  }
  if (!VALID_MEDIA_TYPES.includes(media_type as MediaType)) {
    throw new ApiError("invalid_request", `media_type must be one of: ${VALID_MEDIA_TYPES.join(", ")}.`);
  }
  const mediaType = media_type as MediaType;

  const userId: string = c.get("userId");

  // --- geohash + discoverable window ---
  const geohash = geohashEncode(lat, lng, 9);
  const discoverableAfter = new Date(Date.now() + COOLDOWN_SECONDS * 1000);

  // --- create the memory record (scan_status: pending by default) ---
  // For text memories, no media key is needed — skip signed URL generation.
  const isMediaMemory = mediaType !== "text";

  // Insert first so we have a memory_id before touching storage.
  const memory = await createMemory({
    ownerId: userId,
    lat,
    lng,
    geohash,
    mediaType,
    dropMethod: "pin",
    source: "live",
    mediaKey: null, // updated by storage webhook once upload completes
    discoverableAfter,
  });

  // --- signed PUT URL (skipped for text-only memories) ---
  let signedPutUrl: string | undefined;
  let expiresAt: string | undefined;

  if (isMediaMemory) {
    const storage = await generateSignedPutUrl(memory.id, mediaType);
    signedPutUrl = storage.signedPutUrl;
    expiresAt = storage.expiresAt;
  }

  // Response shape per api-contract §3.1
  return c.json(
    {
      memory_id: memory.id,
      signed_put_url: signedPutUrl ?? null,
      expires_at: expiresAt ?? null,
    },
    201,
  );
});

// ---------------------------------------------------------------------------
// GET /memories/:id
// ---------------------------------------------------------------------------

memoriesRoutes.get("/:id", async (c) => {
  const memoryId = c.req.param("id");
  const userId: string = c.get("userId");

  const memory = await getMemoryByOwner(memoryId, userId);
  if (!memory) throw new ApiError("not_found", "Memory not found.");

  return c.json({
    memory_id: memory.id,
    lat: memory.lat,
    lng: memory.lng,
    geohash: memory.geohash,
    source: memory.source,
    drop_method: memory.drop_method,
    privacy_tier: memory.privacy_tier,
    scan_status: memory.scan_status,
    media_type: memory.media_type,
    media_key: memory.media_key,
    thumbnail_key: memory.thumbnail_key,
    discoverable_after: memory.discoverable_after,
    created_at: memory.created_at,
  });
});
