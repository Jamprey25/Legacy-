// Memory routes (api-contract.md §3, §4):
//   POST /v1/memories            — drop a memory, get back memory_id + signed PUT URL
//   GET  /v1/memories            — paginated owner list (Memory Lane)
//   GET  /v1/memories/:id        — fetch own memory detail (owner only)
//   POST /v1/memories/:id/unlock — proximity+dwell+seal+condition check, return media URL

import { Hono } from "hono";
import { ApiError } from "../lib/errors.js";
import { encode as geohashEncode } from "../lib/geohash.js";
import { generateSignedPutUrl, generateSignedGetUrl } from "../lib/storage.js";
import { createMemory, getMemoryByOwner, getMemoryWithContext, listMemoriesByOwner } from "../db/memories.js";
import { upsertPresencePing, getPresencePing } from "../db/presencePings.js";
import { createFind, getReturnCount, getLastFoundAt } from "../db/finds.js";
import { ownMemoryProximity, othersMemoryProximity } from "../lib/proximity.js";
import { evaluateSeal } from "../lib/sealEval.js";
import { evaluateCondition } from "../lib/conditionEval.js";
import { requireAuth, type AuthVars } from "../middleware/auth.js";

export const memoriesRoutes = new Hono<{ Variables: AuthVars }>();

memoriesRoutes.use("*", requireAuth);

// ---------------------------------------------------------------------------
// GET /memories — paginated oldest-first owner list (Memory Lane)
// ---------------------------------------------------------------------------

const MAX_PAGE_SIZE = 100;
const DEFAULT_PAGE_SIZE = 50;

memoriesRoutes.get("/", async (c) => {
  const userId: string = c.get("userId");
  const limitParam = Number(c.req.query("limit") ?? DEFAULT_PAGE_SIZE);
  const limit = Math.min(isNaN(limitParam) ? DEFAULT_PAGE_SIZE : limitParam, MAX_PAGE_SIZE);
  const cursor = c.req.query("cursor");

  const { memories, nextCursor } = await listMemoriesByOwner({ ownerId: userId, limit, cursor });

  const items = memories.map((m) => ({
    memory_id: m.id,
    drop_date: m.created_at.toISOString().slice(0, 10),
    created_at: m.created_at.toISOString(),
    media_type: m.media_type,
    scan_status: m.scan_status,
    thumbnail_key: m.thumbnail_key,
    privacy_tier: m.privacy_tier,
    drop_method: m.drop_method,
  }));

  return c.json({ memories: items, next_cursor: nextCursor });
});

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

// ---------------------------------------------------------------------------
// POST /memories/:id/unlock
// ---------------------------------------------------------------------------

const DWELL_REQUIRED_SECONDS = 20;

memoriesRoutes.post("/:id/unlock", async (c) => {
  const memoryId = c.req.param("id");
  const userId: string = c.get("userId");

  const body = (await c.req.json().catch(() => null)) as {
    lat: unknown;
    lng: unknown;
    accuracy_m: unknown;
  } | null;
  if (!body) throw new ApiError("invalid_request", "Request body must be JSON.");

  const { lat, lng, accuracy_m } = body;

  if (typeof lat !== "number" || typeof lng !== "number") {
    throw new ApiError("invalid_coordinates", "lat and lng must be numbers.");
  }
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    throw new ApiError("invalid_coordinates", "Coordinates out of range.");
  }
  if (typeof accuracy_m !== "number" || accuracy_m <= 0 || accuracy_m >= 1000) {
    throw new ApiError("invalid_coordinates", "accuracy_m must be > 0 and < 1000.");
  }

  const memory = await getMemoryWithContext(memoryId);
  if (!memory) throw new ApiError("not_found", "Memory not found.");

  const isOwn = memory.owner_id === userId;

  // --- Proximity check ---
  const prox = isOwn
    ? ownMemoryProximity(lat, lng, accuracy_m, memory.lat, memory.lng)
    : othersMemoryProximity(lat, lng, accuracy_m, memory.lat, memory.lng);

  // null = accuracy too low for others' memory → silent not_in_range
  if (!prox || !prox.inBubble) {
    throw new ApiError("not_in_range", "Not close enough to unlock this memory.", 423);
  }

  // --- Dwell check (skip for own memories) ---
  if (!isOwn) {
    const ping = await getPresencePing(memoryId, userId);
    if (!ping) {
      // First check recorded here — can retry after DWELL_REQUIRED_SECONDS.
      await upsertPresencePing(memoryId, userId);
      throw new ApiError("dwell_required", "Stay here a moment longer to open this.", 423, {
        retry_after_s: DWELL_REQUIRED_SECONDS,
      });
    }
    const secondsElapsed = (Date.now() - new Date(ping.last_seen_at).getTime()) / 1000;
    if (secondsElapsed < DWELL_REQUIRED_SECONDS) {
      throw new ApiError("dwell_required", "Stay here a moment longer to open this.", 423, {
        retry_after_s: Math.ceil(DWELL_REQUIRED_SECONDS - secondsElapsed),
      });
    }
  }

  // --- Upsert presence ping (this unlock counts as a proximity check) ---
  await upsertPresencePing(memoryId, userId);

  // --- Seal evaluation ---
  const sealType = (memory.seal_type ?? "none") as Parameters<typeof evaluateSeal>[0];
  const sealConfig = (memory.seal_config ?? {}) as Parameters<typeof evaluateSeal>[1];
  const sealResult = evaluateSeal(sealType, sealConfig, new Date(memory.created_at));
  if (!sealResult.open) {
    throw new ApiError("sealed", "This memory is not yet open.", 423, {
      opens_at: sealResult.opensAt,
      opens_when: sealResult.opensWhen,
    });
  }

  // --- Condition evaluation ---
  if (memory.condition_type && memory.condition_time_fallback) {
    const now = new Date();
    const [returnCount, lastFoundAt] = await Promise.all([
      getReturnCount(memoryId, userId),
      getLastFoundAt(memoryId, userId),
    ]);
    const daysSinceLastFind = lastFoundAt
      ? (now.getTime() - new Date(lastFoundAt).getTime()) / 86_400_000
      : null;

    const condResult = evaluateCondition(
      memory.condition_type as Parameters<typeof evaluateCondition>[0],
      (memory.condition_config ?? {}) as Parameters<typeof evaluateCondition>[1],
      {
        currentHour: now.getUTCHours(),
        currentMonth: now.getUTCMonth() + 1,
        daysSinceLastFind,
        returnCount: returnCount + 1,
        fallbackAt: new Date(memory.condition_time_fallback).toISOString(),
        now,
      },
    );

    if (!condResult.met) {
      throw new ApiError("condition_unmet", "Conditions for this memory are not yet met.", 423, {
        fallback_at: condResult.fallbackAt,
      });
    }
  }

  // --- Generate signed GET URL for media ---
  const media: Array<{ url: string; type: string; expires_at: string }> = [];
  if (memory.media_key && memory.scan_status === "clear") {
    const signed = await generateSignedGetUrl(memory.media_key);
    media.push({
      url: signed.signedGetUrl,
      type: memory.media_type,
      expires_at: signed.expiresAt,
    });
  }

  // --- Record Find ---
  await createFind(memoryId, userId);
  const returnCount = await getReturnCount(memoryId, userId);

  return c.json({
    memory_id: memory.id,
    media,
    caption: memory.caption ?? null,
    drop_date: new Date(memory.created_at).toISOString().slice(0, 10),
    owner_display: isOwn ? "you" : "unknown",
    find_recorded: true,
    return_count: returnCount,
  });
});
