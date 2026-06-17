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
import { createSeal, type SealType } from "../db/seals.js";
import { createCondition, type ConditionType } from "../db/conditions.js";
import { upsertPresencePing, getPresencePing } from "../db/presencePings.js";
import { createFind, getReturnCount, getLastFoundAt } from "../db/finds.js";
import { ownMemoryProximity, othersMemoryProximity } from "../lib/proximity.js";
import { evaluateSeal } from "../lib/sealEval.js";
import { evaluateCondition } from "../lib/conditionEval.js";
import { requireAuth, type AuthVars } from "../middleware/auth.js";
import { rateLimit } from "../middleware/rateLimit.js";

export const memoriesRoutes = new Hono<{ Variables: AuthVars }>();

memoriesRoutes.use("*", requireAuth);

// Per-user write/unlock limits (GET list is unthrottled — cheap, owner-scoped).
// Drops: 20 / hour (a 24h cooldown already gates rediscovery, this guards bulk abuse).
// Unlocks: 30 / minute (legitimate dwell-retry needs a few; this stops brute-forcing).
const dropLimit = rateLimit({ name: "drop", limit: 20, windowSec: 3600, keyBy: "user" });
const unlockLimit = rateLimit({ name: "unlock", limit: 30, windowSec: 60, keyBy: "user" });

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
  drop_method?: unknown;
  privacy_tier?: unknown;
  teaser_text?: unknown;
  caption?: unknown;
  cooldown_hours?: unknown;
  seal?: unknown;
  condition?: unknown;
}

const VALID_MEDIA_TYPES = ["photo", "video", "text"] as const;
type MediaType = (typeof VALID_MEDIA_TYPES)[number];

const VALID_DROP_METHODS = ["pin", "treasure_chest", "note_bottle"] as const;
type DropMethod = (typeof VALID_DROP_METHODS)[number];

const PHASE1_PRIVACY = new Set(["private"]);

function parseSeal(raw: unknown): { sealType: SealType; config: Record<string, unknown> } | null {
  if (raw == null) return null;
  if (typeof raw !== "object" || raw === null || !("type" in raw)) {
    throw new ApiError("invalid_request", "seal must be an object with a type field.");
  }
  const body = raw as Record<string, unknown>;
  const type = body.type;
  if (typeof type !== "string") {
    throw new ApiError("invalid_request", "seal.type must be a string.");
  }

  switch (type) {
    case "fixed_date":
      if (typeof body.open_at !== "string") {
        throw new ApiError("seal_config_invalid", "fixed_date seal requires open_at.");
      }
      return { sealType: "fixed_date", config: { open_at: body.open_at } };
    case "duration":
      if (typeof body.locked_hours !== "number") {
        throw new ApiError("seal_config_invalid", "duration seal requires locked_hours.");
      }
      return { sealType: "duration", config: { locked_hours: body.locked_hours } };
    case "age_based":
      if (typeof body.recipient_dob !== "string" || typeof body.open_at_age !== "number") {
        throw new ApiError("seal_config_invalid", "age_based seal requires recipient_dob and open_at_age.");
      }
      return {
        sealType: "age_based",
        config: { recipient_dob: body.recipient_dob, open_at_age: body.open_at_age },
      };
    case "recurring":
      if (typeof body.window_start !== "string" || typeof body.window_duration_hours !== "number") {
        throw new ApiError("seal_config_invalid", "recurring seal requires window_start and window_duration_hours.");
      }
      return {
        sealType: "recurring",
        config: {
          window_start: body.window_start,
          window_duration_hours: body.window_duration_hours,
        },
      };
    default:
      throw new ApiError("seal_config_invalid", `Unknown seal type: ${type}`);
  }
}

function parseCondition(raw: unknown): {
  conditionType: ConditionType;
  config: Record<string, unknown>;
  timeFallback: string;
} | null {
  if (raw == null) return null;
  if (typeof raw !== "object" || raw === null || !("type" in raw)) {
    throw new ApiError("invalid_request", "condition must be an object with a type field.");
  }
  const body = raw as Record<string, unknown>;
  const type = body.type;
  const fallback = body.time_fallback;
  if (typeof type !== "string") {
    throw new ApiError("invalid_request", "condition.type must be a string.");
  }
  if (typeof fallback !== "string") {
    throw new ApiError("seal_config_invalid", "condition requires time_fallback.");
  }

  switch (type) {
    case "time_of_day":
      return {
        conditionType: "time_of_day",
        config: { after_hour: body.after_hour, before_hour: body.before_hour },
        timeFallback: fallback,
      };
    case "season":
      return {
        conditionType: "season",
        config: { month_start: body.month_start, month_end: body.month_end },
        timeFallback: fallback,
      };
    case "long_absence":
      return {
        conditionType: "long_absence",
        config: { days_since_last_find: body.days_since_last_find },
        timeFallback: fallback,
      };
    case "nth_return":
      return {
        conditionType: "nth_return",
        config: { n: body.n },
        timeFallback: fallback,
      };
    default:
      throw new ApiError("seal_config_invalid", `Unknown condition type: ${type}`);
  }
}


memoriesRoutes.post("/", dropLimit, async (c) => {
  const body = (await c.req.json().catch(() => null)) as PostMemoriesBody | null;
  if (!body) throw new ApiError("invalid_request", "Request body must be JSON.");

  const { lat, lng, accuracy_m, media_type } = body;

  const dropMethodRaw = body.drop_method ?? "pin";
  if (typeof dropMethodRaw !== "string" || !VALID_DROP_METHODS.includes(dropMethodRaw as DropMethod)) {
    throw new ApiError(
      "invalid_request",
      `drop_method must be one of: ${VALID_DROP_METHODS.join(", ")}.`,
    );
  }
  const dropMethod = dropMethodRaw as DropMethod;

  const privacyRaw = body.privacy_tier ?? "private";
  if (typeof privacyRaw !== "string") {
    throw new ApiError("invalid_request", "privacy_tier must be a string.");
  }
  if (!PHASE1_PRIVACY.has(privacyRaw)) {
    throw new ApiError("invalid_request", "Phase 1 only supports privacy_tier: private.");
  }

  const teaserText =
    typeof body.teaser_text === "string" && body.teaser_text.trim().length > 0
      ? body.teaser_text.trim()
      : null;
  const caption =
    typeof body.caption === "string" && body.caption.trim().length > 0
      ? body.caption.trim()
      : null;

  const cooldownHours =
    typeof body.cooldown_hours === "number" && body.cooldown_hours > 0
      ? body.cooldown_hours
      : 24;
  const cooldownSeconds = cooldownHours * 60 * 60;

  const parsedSeal = parseSeal(body.seal);
  const parsedCondition = parseCondition(body.condition);
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
  const discoverableAfter = new Date(Date.now() + cooldownSeconds * 1000);

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
    dropMethod,
    source: "live",
    mediaKey: null,
    discoverableAfter,
    privacyTier: "private",
    teaserText,
    caption,
  });

  if (parsedSeal) {
    await createSeal({
      memoryId: memory.id,
      sealType: parsedSeal.sealType,
      config: parsedSeal.config,
    });
  }

  if (parsedCondition) {
    await createCondition({
      memoryId: memory.id,
      conditionType: parsedCondition.conditionType,
      config: parsedCondition.config,
      timeFallback: parsedCondition.timeFallback,
    });
  }

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

memoriesRoutes.post("/:id/unlock", unlockLimit, async (c) => {
  const memoryId = c.req.param("id");
  if (!memoryId) throw new ApiError("not_found", "Memory not found.");
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
