// Memory repository. Inserts the drop record and fetches memories for a user.
// Coordinates are immutable after insert (no UPDATE on lat/lng/geohash ever).
// The geohash is computed by the caller (lib/geohash.ts) so it can be tested
// independently without a DB connection.

import { sql } from "./client.js";

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
  discoverable_after: Date;
  created_at: Date;
}

/** Insert a new memory. scan_status defaults to 'pending'. Returns the new row. */
export async function createMemory(input: CreateMemoryInput): Promise<MemoryRow> {
  const rows = await sql`
    INSERT INTO memories (
      owner_id, lat, lng, geohash,
      source, drop_method, media_type, media_key,
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
      ${input.discoverableAfter.toISOString()}
    )
    RETURNING *
  `;
  return rows[0] as MemoryRow;
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
  return rows.length > 0 ? (rows[0] as MemoryRow) : null;
}
