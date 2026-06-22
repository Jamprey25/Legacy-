// Memory repository. Inserts the drop record and fetches memories for a user.
// Coordinates are immutable after insert (no UPDATE on lat/lng/geohash ever).
// The geohash is computed by the caller (lib/geohash.ts) so it can be tested
// independently without a DB connection.

import { sql, type Row } from "./client.js";

export interface CreateMemoryInput {
  ownerId: string;
  lat: number;
  lng: number;
  geohash: string; // precision 9
  mediaType: "photo" | "video" | "text";
  dropMethod: "pin" | "treasure_chest" | "import" | "note_bottle" | "prompt";
  source: "live" | "imported";
  mediaKey: string | null;
  discoverableAfter: Date;
  /** When set (imports), used for Memory Lane ordering instead of insert time. */
  createdAt?: Date;
  privacyTier?: "private" | "recipients" | "friends" | "public";
  teaserText?: string | null;
  caption?: string | null;
}

export interface MemoryRow {
  id: string;
  owner_id: string;
  lat: number;
  lng: number;
  geohash: string;
  source: string;
  drop_method: string;
  privacy_tier: string;
  scan_status: string;
  media_type: string;
  media_key: string | null;
  thumbnail_key: string | null;
  caption: string | null;
  teaser_text: string | null;
  discoverable_after: Date;
  created_at: Date;
}

/** Insert a new memory. scan_status defaults to 'pending'. Returns the new row. */
export async function createMemory(input: CreateMemoryInput): Promise<MemoryRow> {
  const createdAt = input.createdAt?.toISOString();
  const rows = createdAt
    ? await sql`
        INSERT INTO memories (
          owner_id, lat, lng, geohash,
          source, drop_method, media_type, media_key,
          privacy_tier, teaser_text, caption,
          discoverable_after, created_at
        ) VALUES (
          ${input.ownerId},
          ${input.lat},
          ${input.lng},
          ${input.geohash},
          ${input.source},
          ${input.dropMethod},
          ${input.mediaType},
          ${input.mediaKey},
          ${input.privacyTier ?? "private"},
          ${input.teaserText ?? null},
          ${input.caption ?? null},
          ${input.discoverableAfter.toISOString()},
          ${createdAt}
        )
        RETURNING *
      `
    : await sql`
        INSERT INTO memories (
          owner_id, lat, lng, geohash,
          source, drop_method, media_type, media_key,
          privacy_tier, teaser_text, caption,
          discoverable_after
        ) VALUES (
          ${input.ownerId},
          ${input.lat},
          ${input.lng},
          ${input.geohash},
          ${input.source},
          ${input.dropMethod},
          ${input.mediaType},
          ${input.mediaKey},
          ${input.privacyTier ?? "private"},
          ${input.teaserText ?? null},
          ${input.caption ?? null},
          ${input.discoverableAfter.toISOString()}
        )
        RETURNING *
      `;
  return rows[0] as unknown as MemoryRow;
}

/** Fetch a single memory by id, owner-only. Returns null if not found or not owner. */
export async function getMemoryByOwner(
  memoryId: string,
  ownerId: string,
): Promise<MemoryRow | null> {
  const rows = await sql`
    SELECT * FROM memories
    WHERE id = ${memoryId} AND owner_id = ${ownerId}
    LIMIT 1
  `;
  return rows.length > 0 ? (rows[0] as unknown as MemoryRow) : null;
}

/** Fetch any memory by id. Caller enforces access rules (e.g. unlock route). */
export async function getMemoryById(memoryId: string): Promise<MemoryRow | null> {
  const rows = await sql`SELECT * FROM memories WHERE id = ${memoryId} LIMIT 1`;
  return rows.length > 0 ? (rows[0] as unknown as MemoryRow) : null;
}

/** Full memory context including seal + condition rows (joined). Used at unlock time. */
export interface MemoryWithContext extends MemoryRow {
  seal_type: string | null;
  seal_config: Row | null;
  condition_type: string | null;
  condition_config: Row | null;
  condition_time_fallback: Date | null;
}

export async function getMemoryWithContext(memoryId: string): Promise<MemoryWithContext | null> {
  const rows = await sql`
    SELECT
      m.*,
      s.seal_type,
      s.config AS seal_config,
      c.condition_type,
      c.config AS condition_config,
      c.condition_time_fallback
    FROM memories m
    LEFT JOIN seals s ON s.memory_id = m.id
    LEFT JOIN conditions c ON c.memory_id = m.id
    WHERE m.id = ${memoryId}
    LIMIT 1
  `;
  return rows.length > 0 ? (rows[0] as unknown as MemoryWithContext) : null;
}

export type MemorySort = "oldest" | "newest";

export interface ListMemoriesOptions {
  ownerId: string;
  limit: number;
  cursor?: string; // opaque base64url JSON { created_at, id } or legacy ISO timestamp
  sort?: MemorySort; // default "oldest" (preserves prior behaviour)
  mediaType?: "photo" | "video" | "text"; // optional filter
}

export interface ListMemoriesResult {
  memories: MemoryRow[];
  nextCursor: string | null;
}

interface ListCursor {
  createdAt: string;
  id: string;
}

function encodeListCursor(row: MemoryRow): string {
  const payload = JSON.stringify({
    created_at: new Date(row.created_at).toISOString(),
    id: row.id,
  });
  return Buffer.from(payload, "utf8").toString("base64url");
}

function decodeListCursor(raw: string): ListCursor | null {
  try {
    const parsed = JSON.parse(Buffer.from(raw, "base64url").toString("utf8")) as {
      created_at?: string;
      id?: string;
    };
    if (parsed.created_at && parsed.id) {
      return { createdAt: parsed.created_at, id: parsed.id };
    }
  } catch {
    // fall through — legacy cursor was a bare ISO timestamp
  }
  try {
    const legacy = Buffer.from(raw, "base64url").toString("utf8");
    if (legacy) return { createdAt: legacy, id: "" };
  } catch {
    // ignore malformed cursor — start from beginning
  }
  return null;
}

/**
 * Paginated list of own memories. Defaults to oldest-first; pass sort: "newest" to
 * reverse. Cursor is opaque base64url JSON ({ created_at, id }) and is direction-aware:
 * oldest paginates forward in time, newest paginates backward. An optional mediaType
 * narrows the list (photo/video/text).
 *
 * Built with the neon ordinary-function form (`sql(text, params)`) so the optional sort,
 * filter, and cursor compose without a combinatorial explosion of tagged-template
 * branches. The sort direction is the only interpolated token and is derived from a
 * closed enum (never raw input), so this stays injection-safe; all values are bind params.
 */
export async function listMemoriesByOwner(opts: ListMemoriesOptions): Promise<ListMemoriesResult> {
  const { ownerId, limit } = opts;
  const sort: MemorySort = opts.sort === "newest" ? "newest" : "oldest";
  const cmp = sort === "newest" ? "<" : ">";
  const order = sort === "newest" ? "DESC" : "ASC";
  const cursor = opts.cursor ? decodeListCursor(opts.cursor) : null;

  const conditions: string[] = ["owner_id = $1"];
  const params: unknown[] = [ownerId];

  if (opts.mediaType) {
    params.push(opts.mediaType);
    conditions.push(`media_type = $${params.length}`);
  }

  if (cursor) {
    if (cursor.id) {
      params.push(cursor.createdAt, cursor.id);
      const cAt = `$${params.length - 1}`;
      const cId = `$${params.length}`;
      conditions.push(`(created_at ${cmp} ${cAt} OR (created_at = ${cAt} AND id ${cmp} ${cId}))`);
    } else {
      params.push(cursor.createdAt);
      conditions.push(`created_at ${cmp} $${params.length}`);
    }
  }

  params.push(limit + 1);
  const queryText = `
    SELECT * FROM memories
    WHERE ${conditions.join(" AND ")}
    ORDER BY created_at ${order}, id ${order}
    LIMIT $${params.length}
  `;

  const rows = (await sql(queryText, params)) as unknown as MemoryRow[];
  const hasMore = rows.length > limit;
  const page = hasMore ? rows.slice(0, limit) : rows;
  const lastRow = page[page.length - 1];
  const nextCursor = hasMore && lastRow ? encodeListCursor(lastRow) : null;

  return { memories: page, nextCursor };
}

export interface NearbyMemory extends MemoryRow {
  seal_type: string | null;
  condition_type: string | null;
  condition_time_fallback: Date | null;
}

/**
 * Find eligible memories within the coarse geohash zone (precision-5 prefix).
 * Checks current cell + 8 neighbours via LEFT(geohash,5) = ANY(array).
 * Phase 1: private tier only → owner_id = requestingUserId.
 * Eligibility: scan_status = clear, discoverable_after elapsed.
 */
/**
 * Set media_key and flip scan_status to 'clear' after a successful upload + pipeline pass.
 * Returns the updated row, or null if the memory doesn't exist.
 */
export async function updateMemoryAfterUpload(
  memoryId: string,
  mediaKey: string,
): Promise<MemoryRow | null> {
  const rows = await sql`
    UPDATE memories
    SET media_key = ${mediaKey},
        scan_status = 'clear'
    WHERE id = ${memoryId}
    RETURNING *
  `;
  return rows.length > 0 ? (rows[0] as unknown as MemoryRow) : null;
}

/** Set the thumbnail_key after server-side thumbnail generation (post-clear, best-effort). */
export async function setThumbnailKey(memoryId: string, thumbnailKey: string): Promise<void> {
  await sql`
    UPDATE memories
    SET thumbnail_key = ${thumbnailKey}
    WHERE id = ${memoryId}
  `;
}

export async function findNearbyMemories(
  coarseHash: string,
  neighbourHashes: string[],
  requestingUserId: string,
): Promise<NearbyMemory[]> {
  // Truncate memory geohash to precision 5 for zone matching.
  const zoneHashes = [coarseHash, ...neighbourHashes];
  const rows = await sql`
    SELECT m.*,
           s.seal_type,
           c.condition_type,
           c.condition_time_fallback
    FROM memories m
    LEFT JOIN seals s ON s.memory_id = m.id
    LEFT JOIN conditions c ON c.memory_id = m.id
    WHERE m.owner_id = ${requestingUserId}
      AND m.scan_status = 'clear'
      AND m.discoverable_after <= now()
      AND left(m.geohash, 5) = ANY(${zoneHashes})
  `;
  return rows as unknown as NearbyMemory[];
}

export interface CoarseZoneCount {
  geohash_prefix: string; // precision-7 cell (~150m) — no coordinates ever returned
  count: number;
}

/**
 * Count others' eligible memories by precision-7 geohash prefix within the coarse zone.
 * Returns cell prefixes + counts only — never coordinates or identity (DEC-15).
 * Phase 1: privacy_tier = 'private', so this will return 0 rows until Phase 2 social.
 * Kept now so iOS can wire the rendering; will light up naturally when social ships.
 */
export async function countNearbyZones(
  coarseHash: string,
  neighbourHashes: string[],
  requestingUserId: string,
): Promise<CoarseZoneCount[]> {
  const zoneHashes = [coarseHash, ...neighbourHashes];
  const rows = await sql`
    SELECT left(geohash, 7) AS geohash_prefix,
           count(*)::int    AS count
    FROM memories
    WHERE owner_id != ${requestingUserId}
      AND scan_status = 'clear'
      AND discoverable_after <= now()
      AND left(geohash, 5) = ANY(${zoneHashes})
    GROUP BY left(geohash, 7)
  `;
  return rows as unknown as CoarseZoneCount[];
}
