// Memory routes (api-contract.md §3, §4, §5):
//   POST /v1/memories            — drop a memory, get back memory_id + signed PUT URL
//   GET  /v1/memories            — paginated owner list (Memory Lane)
//   GET  /v1/memories/:id        — fetch own memory detail (owner only)
//   DELETE /v1/memories/:id      — owner-only hard delete ("undrop")
//   POST /v1/memories/:id/unlock — proximity+dwell+seal+condition check, return media URL
//   POST /v1/memories/import     — batch-create private memories from on-device clusters

import { Hono } from "hono";
import { del } from "@vercel/blob";
import { ApiError } from "../lib/errors.js";
import { encode as geohashEncode } from "../lib/geohash.js";
import { generateSignedPutUrl, generateSignedGetUrl, usesClientUpload } from "../lib/storage.js";
import { createMemory, deleteMemoryByOwner, getMemoryByOwner, getMemoryWithContext, listMemoriesByOwner } from "../db/memories.js";
import { createSeal, type SealType } from "../db/seals.js";
import { createCondition, type ConditionType } from "../db/conditions.js";
import { upsertPresencePing, getPresencePing } from "../db/presencePings.js";
import { createFind, getReturnCount, getLastFoundAt } from "../db/finds.js";
import { ownMemoryProximity, othersMemoryProximity } from "../lib/proximity.js";
import { evaluateSeal } from "../lib/sealEval.js";
import { evaluateCondition } from "../lib/conditionEval.js";
import { requireAuth, type AuthVars } from "../middleware/auth.js";
import { rateLimit } from "../middleware/rateLimit.js";
import { validateLocationInput } from "../lib/locationInput.js";
import { audit } from "../lib/audit.js";
import { verifyAppAttestForRequest } from "../lib/appAttestRequest.js";
import { storeImportResult, findImportByKey } from "../db/imports.js";
import { isRecipientOfMemory } from "../db/summons.js";
import {
  createMediaSlots,
  getMemoryUploadCounts,
  listMediaByMemory,
  listMediaKeysByMemory,
} from "../db/memoryMedia.js";

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

const VALID_SORTS = ["oldest", "newest"] as const;

memoriesRoutes.get("/", async (c) => {
  const userId: string = c.get("userId");
  const limitParam = Number(c.req.query("limit") ?? DEFAULT_PAGE_SIZE);
  const limit = Math.min(isNaN(limitParam) ? DEFAULT_PAGE_SIZE : limitParam, MAX_PAGE_SIZE);
  const cursor = c.req.query("cursor");

  // sort: oldest (default, back-compat) | newest. Unknown values fall back to oldest.
  const sortParam = c.req.query("sort");
  const sort = VALID_SORTS.includes(sortParam as (typeof VALID_SORTS)[number])
    ? (sortParam as "oldest" | "newest")
    : "oldest";

  // media_type: optional filter. Unknown values are ignored (no filter).
  const mediaTypeParam = c.req.query("media_type");
  const mediaType =
    mediaTypeParam === "photo" || mediaTypeParam === "video" || mediaTypeParam === "text"
      ? mediaTypeParam
      : undefined;

  const { memories, nextCursor } = await listMemoriesByOwner({
    ownerId: userId,
    limit,
    cursor,
    sort,
    mediaType,
  });

  // Resolve media URLs for clear memories. Prefer thumbnail_url for the grid, but ALSO
  // return media_url so the client can render the real image when no thumbnail exists
  // (server-side thumbnailing is best-effort and may be absent for imports or if sharp
  // is unavailable). Both are owner-only own media — same source GET /:id already exposes,
  // no new privacy surface. For Vercel Blob these resolve to the stored public URL (no
  // network); for S3/R2 they are short-TTL signed GETs.
  const items = await Promise.all(
    memories.map(async (m) => {
      let thumbnailUrl: string | null = null;
      let mediaUrl: string | null = null;
      if (m.scan_status === "clear") {
        if (m.thumbnail_key) thumbnailUrl = (await generateSignedGetUrl(m.thumbnail_key)).signedGetUrl;
        if (m.media_key) mediaUrl = (await generateSignedGetUrl(m.media_key)).signedGetUrl;
      }
      return {
        memory_id: m.id,
        drop_date: m.created_at.toISOString().slice(0, 10),
        created_at: m.created_at.toISOString(),
        lat: m.lat,
        lng: m.lng,
        media_type: m.media_type,
        scan_status: m.scan_status,
        thumbnail_url: thumbnailUrl,
        media_url: mediaUrl,
        // Cleared photo count — drives the grid "multi-photo" badge. Hero-only/text = 1/0.
        photo_count: m.media_count ?? (m.media_key ? 1 : 0),
        caption: m.caption ?? null,
        teaser_text: m.teaser_text ?? null,
        privacy_tier: m.privacy_tier,
        drop_method: m.drop_method,
      };
    }),
  );

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
  attestation?: unknown;
  challenge_token?: unknown;
}

const VALID_MEDIA_TYPES = ["photo", "video", "text"] as const;
type MediaType = (typeof VALID_MEDIA_TYPES)[number];

const VALID_DROP_METHODS = ["pin", "treasure_chest", "note_bottle"] as const;
type DropMethod = (typeof VALID_DROP_METHODS)[number];

// Phase 2 (recipient ACL): drops may now target the recipients tier. Friends and
// public stay rejected until their discovery gates ship.
const ALLOWED_PRIVACY = new Set(["private", "recipients"]);

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

  await verifyAppAttestForRequest(c, body);

  const { media_type } = body;
  const { lat, lng, accuracyM: accuracy_m } = validateLocationInput(body.lat, body.lng, body.accuracy_m);

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
  if (!ALLOWED_PRIVACY.has(privacyRaw)) {
    throw new ApiError("invalid_request", "privacy_tier must be one of: private, recipients.");
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

  // --- signed PUT URL (skipped for text-only memories AND for client-upload backends) ---
  // Vercel Blob uses a client-token handshake (POST /v1/uploads), so no presigned PUT
  // here — upload is null and the client switches to the handshake flow.
  let signedPutUrl: string | undefined;
  let expiresAt: string | undefined;

  if (isMediaMemory && !usesClientUpload()) {
    const storage = await generateSignedPutUrl(memory.id, mediaType);
    signedPutUrl = storage.signedPutUrl;
    expiresAt = storage.expiresAt;
  }

  // Audit: non-locational facts only (no lat/lng/geohash — privacy gate).
  audit(c, "memory.drop", {
    memory_id: memory.id,
    media_type: mediaType,
    drop_method: dropMethod,
    sealed: parsedSeal !== null,
    conditional: parsedCondition !== null,
  });

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
// POST /memories/import — batch-create private memories from on-device clusters
// (api-contract.md §5)
// Registered before /:id so "import" is not consumed as an id param.
// ---------------------------------------------------------------------------

// One import session = one request that can carry up to 200 clusters, so this is a
// session budget, not a memory budget. 5/hr was far too tight (it read as "crashes after
// 5 imports"); 30 leaves room to import in batches.
const importLimit = rateLimit({ name: "import", limit: 30, windowSec: 3600, keyBy: "user" });

// Anti-abuse backstop on photos per imported memory — NOT a curation cap. A real visit is
// at most a few hundred photos; this only stops a pathological/malicious count.
const MAX_PHOTOS_PER_MEMORY = 1000;

memoriesRoutes.post("/import", importLimit, async (c) => {
  const userId: string = c.get("userId");

  const body = await c.req.json<{
    idempotency_key?: unknown;
    clusters?: unknown;
  }>().catch(() => null);

  if (!body) throw new ApiError("invalid_request", "Request body must be JSON.");

  const idempotencyKey = typeof body.idempotency_key === "string" ? body.idempotency_key.trim() : null;
  if (!idempotencyKey) {
    throw new ApiError("invalid_request", "Missing idempotency_key.");
  }

  // Idempotency replay — return the prior result without re-inserting.
  const prior = await findImportByKey(userId, idempotencyKey);
  if (prior) {
    return c.json(prior, 201);
  }

  if (!Array.isArray(body.clusters) || body.clusters.length === 0) {
    throw new ApiError("invalid_request", "clusters must be a non-empty array.");
  }

  if (body.clusters.length > 200) {
    throw new ApiError("invalid_request", "clusters exceeds maximum of 200 per import.");
  }

  const clusters = body.clusters as Array<{
    lat?: unknown;
    lng?: unknown;
    captured_at?: unknown;
    asset_count?: unknown;
    photo_count?: unknown;
  }>;

  clusters.forEach((cl, i) => {
    const lat = typeof cl.lat === "number" ? cl.lat : NaN;
    const lng = typeof cl.lng === "number" ? cl.lng : NaN;
    if (isNaN(lat) || lat < -90 || lat > 90 || isNaN(lng) || lng < -180 || lng > 180) {
      throw new ApiError("invalid_request", `clusters[${i}]: invalid lat/lng.`);
    }
    if (!cl.captured_at || typeof cl.captured_at !== "string") {
      throw new ApiError("invalid_request", `clusters[${i}]: missing captured_at.`);
    }
  });

  // How many photos the client will upload for each cluster (the whole visit, not a cap).
  // Defaults to 1 for older clients. Clamped to a sane anti-abuse ceiling.
  const photoCountFor = (cl: { photo_count?: unknown }): number => {
    const raw = typeof cl.photo_count === "number" ? Math.floor(cl.photo_count) : 1;
    return Math.max(1, Math.min(raw, MAX_PHOTOS_PER_MEMORY));
  };

  const importId = crypto.randomUUID();
  const memories = await Promise.all(
    clusters.map(async (cl, i) => {
      const lat = cl.lat as number;
      const lng = cl.lng as number;
      const capturedAt = new Date(cl.captured_at as string);
      const geohash = geohashEncode(lat, lng, 9);
      const photoCount = photoCountFor(cl);

      const memory = await createMemory({
        ownerId: userId,
        lat,
        lng,
        geohash,
        mediaType: "photo",
        dropMethod: "import",
        source: "imported",
        mediaKey: null,
        discoverableAfter: capturedAt,
        createdAt: capturedAt,
        privacyTier: "private",
      });

      // Pre-create one pending media slot per photo (positions 0..photoCount-1). The client
      // then uploads each via POST /uploads/direct with X-Media-Position.
      await createMediaSlots(memory.id, photoCount, "photo");

      // Blob: client-upload handshake (POST /v1/uploads). S3/R2/stub: presigned PUT.
      let upload: { signed_put_url: string; expires_at: string } | null = null;
      if (!usesClientUpload()) {
        const { signedPutUrl, expiresAt } = await generateSignedPutUrl(memory.id, "photo");
        upload = { signed_put_url: signedPutUrl, expires_at: expiresAt };
      }

      return { cluster_index: i, memory_id: memory.id, media_count: photoCount, upload };
    }),
  );

  await storeImportResult(userId, idempotencyKey, importId, memories);

  audit(c, "import", { import_id: importId, cluster_count: memories.length });

  return c.json({ import_id: importId, memories }, 201);
});

// ---------------------------------------------------------------------------
// GET /memories/:id
// ---------------------------------------------------------------------------

/**
 * Project a memory's cleared photos into an ordered, signed media array. Hero is position 0.
 * Pending/blocked slots are omitted — no peeking before the pipeline clears each photo.
 */
async function clearedMediaFor(memoryId: string): Promise<
  Array<{ url: string; thumbnail_url: string | null; type: string; position: number; expires_at: string }>
> {
  const rows = await listMediaByMemory(memoryId);
  const out: Array<{
    url: string;
    thumbnail_url: string | null;
    type: string;
    position: number;
    expires_at: string;
  }> = [];
  for (const m of rows) {
    if (m.scan_status !== "clear" || !m.media_key) continue;
    const signed = await generateSignedGetUrl(m.media_key);
    const thumb = m.thumbnail_key ? await generateSignedGetUrl(m.thumbnail_key) : null;
    out.push({
      url: signed.signedGetUrl,
      thumbnail_url: thumb?.signedGetUrl ?? null,
      type: m.media_type,
      position: m.position,
      expires_at: signed.expiresAt,
    });
  }
  return out;
}

type UploadLifecycleStage = "creating" | "uploading_hero" | "uploading_extras" | "partial_failure" | "ready";

async function uploadStatusFor(memoryId: string, memoryScanStatus: string, hasHeroKey: boolean): Promise<{
  stage: UploadLifecycleStage;
  total_media: number;
  uploaded_media: number;
  pending_media: number;
  failed_media: number;
  hero_ready: boolean;
}> {
  const counts = await getMemoryUploadCounts(memoryId);

  // Live one-photo drops may not have a pre-created slot; fall back to memory row status.
  if (counts.total === 0) {
    const total = hasHeroKey || memoryScanStatus === "clear" ? 1 : 0;
    const uploaded = memoryScanStatus === "clear" && total > 0 ? 1 : 0;
    return {
      stage: uploaded > 0 ? "ready" : "creating",
      total_media: total,
      uploaded_media: uploaded,
      pending_media: Math.max(total - uploaded, 0),
      failed_media: 0,
      hero_ready: uploaded > 0,
    };
  }

  const pending = Math.max(counts.total - counts.clear - counts.failed, 0);
  let stage: UploadLifecycleStage;
  if (counts.failed > 0 && counts.clear === 0) {
    stage = "partial_failure";
  } else if (counts.failed > 0) {
    stage = "partial_failure";
  } else if (!counts.heroClear) {
    stage = "uploading_hero";
  } else if (pending > 0) {
    stage = "uploading_extras";
  } else {
    stage = "ready";
  }

  return {
    stage,
    total_media: counts.total,
    uploaded_media: counts.clear,
    pending_media: pending,
    failed_media: counts.failed,
    hero_ready: counts.heroClear,
  };
}

memoriesRoutes.get("/:id", async (c) => {
  const memoryId = c.req.param("id");
  const userId: string = c.get("userId");

  const memory = await getMemoryByOwner(memoryId, userId);
  if (!memory) throw new ApiError("not_found", "Memory not found.");

  // Full ordered photo set. media_url/thumbnail_url remain as the hero (position 0) for
  // back-compat with clients that haven't adopted the array yet.
  const [media, uploadStatus, returnCount, lastFoundAt] = await Promise.all([
    clearedMediaFor(memoryId),
    uploadStatusFor(memoryId, memory.scan_status, Boolean(memory.media_key)),
    getReturnCount(memoryId, userId),
    getLastFoundAt(memoryId, userId),
  ]);
  const hero = media[0] ?? null;

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
    media_url: hero?.url ?? null,
    thumbnail_url: hero?.thumbnail_url ?? null,
    media: media.map(({ url, thumbnail_url, type, position }) => ({ url, thumbnail_url, type, position })),
    upload_status: uploadStatus,
    discoverable_after: memory.discoverable_after,
    created_at: memory.created_at,
    return_count: returnCount,
    last_found_at: lastFoundAt?.toISOString() ?? null,
  });
});

// ---------------------------------------------------------------------------
// DELETE /memories/:id
// ---------------------------------------------------------------------------

memoriesRoutes.delete("/:id", async (c) => {
  const memoryId = c.req.param("id");
  const userId: string = c.get("userId");

  // Owner-only delete. 404 for not found/non-owner to avoid leaking existence.
  const existing = await getMemoryByOwner(memoryId, userId);
  if (!existing) throw new ApiError("not_found", "Memory not found.");

  // Collect keys before delete (FK cascade removes memory_media rows).
  const mediaKeys = await listMediaKeysByMemory(memoryId);
  const keys = new Set<string>(mediaKeys);
  if (existing.media_key) keys.add(existing.media_key);
  if (existing.thumbnail_key) keys.add(existing.thumbnail_key);

  await deleteMemoryByOwner(memoryId, userId);
  // Blob cleanup is awaited so a 204 implies both DB + storage deletion succeeded.
  const STORAGE = process.env.STORAGE_BACKEND ?? "stub";
  if (STORAGE === "vercel-blob" && keys.size > 0) {
    const deletions = await Promise.allSettled(Array.from(keys).map((key) => del(key)));
    const failed = deletions.filter((d) => d.status === "rejected").length;
    if (failed > 0) {
      throw new ApiError("internal_error", "Memory removed, but blob cleanup failed.");
    }
  }

  audit(c, "memory.delete", { memory_id: memoryId, media_asset_count: keys.size });
  return new Response(null, { status: 204 });
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
    attestation?: unknown;
    challenge_token?: unknown;
  } | null;
  if (!body) throw new ApiError("invalid_request", "Request body must be JSON.");

  await verifyAppAttestForRequest(c, body);

  const { lat, lng, accuracyM: accuracy_m } = validateLocationInput(body.lat, body.lng, body.accuracy_m);

  const memory = await getMemoryWithContext(memoryId);
  if (!memory) throw new ApiError("not_found", "Memory not found.");

  const isOwn = memory.owner_id === userId;

  // --- Content eligibility (SEC-P2-3 + recipient ACL) ---
  // Non-owners must pass the tier gate. A summons deep link exposes the memory ID,
  // so possession of the ID must never be sufficient — membership is checked here.
  if (!isOwn) {
    switch (memory.privacy_tier) {
      case "recipients": {
        const allowed = await isRecipientOfMemory(memoryId, userId);
        if (!allowed) {
          throw new ApiError("forbidden", "This memory is not shared with you.");
        }
        break;
      }
      // friends/public: discovery gates not shipped — nothing is shared at these
      // tiers yet, and drops at them are rejected. Deny defensively regardless.
      default:
        throw new ApiError("forbidden", "This memory is private.");
    }
  }
  if (memory.scan_status !== "clear") {
    throw new ApiError("not_in_range", "Not close enough to unlock this memory.", 423);
  }
  if (!isOwn && new Date(memory.discoverable_after) > new Date()) {
    throw new ApiError("not_in_range", "Not close enough to unlock this memory.", 423);
  }

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

  // --- Signed GET URLs for the full photo set (hero first) ---
  const media = (await clearedMediaFor(memoryId)).map(({ url, type, expires_at, position }) => ({
    url,
    type,
    expires_at,
    position,
  }));

  if (memory.media_type !== "text" && media.length === 0) {
    throw new ApiError("not_in_range", "Not close enough to unlock this memory.", 423);
  }

  // --- Record Find ---
  await createFind(memoryId, userId);
  const returnCount = await getReturnCount(memoryId, userId);

  // Audit: outcome + memory id only (no coordinates — privacy gate).
  audit(c, "unlock", { memory_id: memory.id, result: "success", is_own: isOwn });

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

