// Discovery routes (api-contract.md §4):
//   POST /v1/discovery/scan — location submitted, validated, discarded; teasers returned

import { Hono } from "hono";
import { ApiError } from "../lib/errors.js";
import { encode as geohashEncode, neighbours } from "../lib/geohash.js";
import { ownMemoryProximity, othersMemoryProximity } from "../lib/proximity.js";
import { generateSignedGetUrl } from "../lib/storage.js";
import { findNearbyMemories } from "../db/memories.js";
import { upsertPresencePing } from "../db/presencePings.js";
import { requireAuth, type AuthVars } from "../middleware/auth.js";
import { rateLimit } from "../middleware/rateLimit.js";

export const discoveryRoutes = new Hono<{ Variables: AuthVars }>();

discoveryRoutes.use("*", requireAuth);
// Per-user scan cap — foreground scans are movement-gated client-side, but guard the
// server against a runaway/abusive client. 60 scans / minute per user.
discoveryRoutes.use("*", rateLimit({ name: "scan", limit: 60, windowSec: 60, keyBy: "user" }));

// ---------------------------------------------------------------------------
// POST /discovery/scan
// ---------------------------------------------------------------------------

discoveryRoutes.post("/scan", async (c) => {
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

  const userId: string = c.get("userId");

  // Coarse zone = precision-5 prefix (~4.9km cell). Query this cell + 8 neighbours.
  const coarseHash = geohashEncode(lat, lng, 5);
  const neighbourHashes = neighbours(coarseHash);
  const nearby = await findNearbyMemories(coarseHash, neighbourHashes, userId);

  if (nearby.length === 0) {
    return new Response(null, { status: 204 });
  }

  // Coordinates are validated here and discarded immediately.
  const teasers = await Promise.all(
    nearby.map(async (mem) => {
      const isOwn = mem.owner_id === userId;

      const prox = isOwn
        ? ownMemoryProximity(lat, lng, accuracy_m, mem.lat, mem.lng)
        : othersMemoryProximity(lat, lng, accuracy_m, mem.lat, mem.lng);

      // null from othersMemoryProximity = accuracy too low → silently skip
      if (!prox) return null;

      // Dwell check #1: scan counts as the first proximity check for in-range memories.
      if (prox.inBubble) {
        await upsertPresencePing(mem.id, userId);
      }

      // Thumbnail URL — null for text, sealed thumbnails, or pending scan_status.
      let thumbnailUrl: string | null = null;
      if (mem.thumbnail_key && mem.scan_status === "clear") {
        const signed = await generateSignedGetUrl(mem.thumbnail_key);
        thumbnailUrl = signed.signedGetUrl;
      }

      return {
        memory_id: mem.id,
        thumbnail_url: thumbnailUrl,
        drop_date: mem.created_at.toISOString().slice(0, 10),
        owner_display: isOwn ? "you" : "unknown", // Phase 2: display names for others
        is_own: isOwn,
        in_range: prox.inBubble,
        warmth: prox.warmth,
        scan_status: mem.scan_status,
      };
    }),
  );

  const filteredTeasers = teasers.filter(Boolean);

  if (filteredTeasers.length === 0) {
    return new Response(null, { status: 204 });
  }

  return c.json({ teasers: filteredTeasers });
});
