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
  const rows = await sql`
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

export interface ListMemoriesOptions {
  ownerId: string;
  limit: number;
  cursor?: string; // opaque: base64url-encoded ISO timestamp of last seen created_at
}

export interface ListMemoriesResult {
  memories: MemoryRow[];
  nextCursor: string | null;
}

/**
 * Paginated oldest-first list of own memories. Cursor is opaque base64url ISO timestamp.
 */
export async function listMemoriesByOwner(opts: ListMemoriesOptions): Promise<ListMemoriesResult> {
  const { ownerId, limit } = opts;
  let cursorDate: string | null = null;
  if (opts.cursor) {
    try {
      cursorDate = Buffer.from(opts.cursor, "base64url").toString("utf8");
    } catch {
      // ignore malformed cursor — start from beginning
    }
  }

  const rows = cursorDate
    ? await sql`
        SELECT * FROM memories
        WHERE owner_id = ${ownerId} AND created_at > ${cursorDate}
        ORDER BY created_at ASC
        LIMIT ${limit + 1}
      `
    : await sql`
        SELECT * FROM memories
        WHERE owner_id = ${ownerId}
        ORDER BY created_at ASC
        LIMIT ${limit + 1}
      `;

  const typedRows = rows as unknown as MemoryRow[];
  const hasMore = typedRows.length > limit;
  const page = hasMore ? typedRows.slice(0, limit) : typedRows;
  const lastRow = page[page.length - 1];
  const nextCursor =
    hasMore && lastRow
      ? Buffer.from(new Date(lastRow.created_at).toISOString(), "utf8").toString("base64url")
      : null;

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
