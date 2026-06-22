// Discovery routes (api-contract.md §4):
//   POST /v1/discovery/scan — location submitted, validated, discarded; teasers returned

import { Hono } from "hono";
import { ApiError } from "../lib/errors.js";
import { encode as geohashEncode, neighbours } from "../lib/geohash.js";
import { ownMemoryProximity, othersMemoryProximity } from "../lib/proximity.js";
import { generateSignedGetUrl } from "../lib/storage.js";
import { findNearbyMemories, countNearbyZones } from "../db/memories.js";
import { validateLocationInput } from "../lib/locationInput.js";
import { audit } from "../lib/audit.js";
import { upsertPresencePing, debouncedWarmth, type WarmthBand } from "../db/presencePings.js";
import { requireAuth, type AuthVars } from "../middleware/auth.js";
import { rateLimit } from "../middleware/rateLimit.js";
import { getApnsTokensForUser, clearApnsToken } from "../db/sessions.js";
import { sendProximityPush } from "../lib/apns.js";

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

  const { lat, lng, accuracyM: accuracy_m } = validateLocationInput(body.lat, body.lng, body.accuracy_m);

  const userId: string = c.get("userId");

  // Coarse zone = precision-5 prefix (~4.9km cell). Query this cell + 8 neighbours.
  const coarseHash = geohashEncode(lat, lng, 5);
  const neighbourHashes = neighbours(coarseHash);
  const [nearby, zones] = await Promise.all([
    findNearbyMemories(coarseHash, neighbourHashes, userId),
    countNearbyZones(coarseHash, neighbourHashes, userId),
  ]);

  if (nearby.length === 0 && zones.length === 0) {
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

      // Warmth debounce: upgrades immediate, downgrades held for 2 scans ≥15s.
      const emittedWarmth = await debouncedWarmth(mem.id, userId, prox.warmth as WarmthBand);

      // Thumbnail URL — null for text, sealed thumbnails, or pending scan_status.
      let thumbnailUrl: string | null = null;
      if (mem.thumbnail_key && mem.scan_status === "clear") {
        const signed = await generateSignedGetUrl(mem.thumbnail_key);
        thumbnailUrl = signed.signedGetUrl;
      }

      // Pin reveal: expose coordinates only when user is within 100m reveal radius.
      // For own memories: always revealed (they placed it). For others: only at reveal radius.
      // This is the only place lat/lng ever leave the server for a non-owner (DEC-15 gate).
      const PIN_REVEAL_RADIUS_M = 100;
      const pinRevealed = isOwn || prox.distanceM <= PIN_REVEAL_RADIUS_M;

      return {
        memory_id: mem.id,
        thumbnail_url: thumbnailUrl,
        drop_date: mem.created_at.toISOString().slice(0, 10),
        owner_display: isOwn ? "you" : "unknown", // Phase 2: display names for others
        is_own: isOwn,
        in_range: prox.inBubble,
        warmth: emittedWarmth,
        scan_status: mem.scan_status,
        pin_revealed: pinRevealed,
        // Coordinates only when revealed — omitted entirely otherwise (never null).
        ...(pinRevealed ? { lat: mem.lat, lng: mem.lng } : {}),
      };
    }),
  );

  const filteredTeasers = teasers.filter(Boolean);

  // Audit: count only — never coordinates (DEC-17 / privacy gate).
  audit(c, "scan", { teaser_count: filteredTeasers.length });

  if (filteredTeasers.length === 0 && zones.length === 0) {
    return new Response(null, { status: 204 });
  }

  // Fire-and-forget proximity push if any teasers are in-range.
  // Runs after response is assembled; never blocks or throws to the caller.
  const hasInRange = filteredTeasers.some((t) => t && t.in_range);
  if (hasInRange) {
    getApnsTokensForUser(userId).then((tokens) => {
      for (const token of tokens) {
        sendProximityPush(token).then((result) => {
          if (!result.ok && result.unregistered) {
            clearApnsToken(userId, token).catch(() => {});
          }
        }).catch(() => {});
      }
    }).catch(() => {});
  }

  return c.json({
    teasers: filteredTeasers,
    // Precision-7 cell prefixes (~150m) with counts of others' eligible memories.
    // Never contains coordinates or identity — only geohash prefix + count (DEC-15).
    zones: zones.map((z) => ({ geohash_prefix: z.geohash_prefix, count: z.count })),
  });
});
