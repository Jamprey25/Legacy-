// memory_media repository (migration 0012_memory_media.sql).
// A memory holds many photos; this stores every one. Position 0 is the hero and is also
// mirrored onto memories.media_key (see updateMemoryAfterUpload) so the discovery hot path
// is untouched. Reads (GET /:id, unlock) project the ordered array from here.

import { sql } from "./client.js";

export interface MemoryMediaRow {
  id: string;
  memory_id: string;
  position: number;
  media_type: string;
  media_key: string | null;
  thumbnail_key: string | null;
  scan_status: string;
  created_at: Date;
}

/**
 * Pre-create `count` pending media slots (positions 0..count-1) for a freshly inserted
 * memory. Idempotent per (memory_id, position) so a retried import doesn't duplicate slots.
 */
export async function createMediaSlots(
  memoryId: string,
  count: number,
  mediaType: "photo" | "video" = "photo",
): Promise<void> {
  if (count <= 0) return;
  // One multi-row insert (positions 0..count-1); ON CONFLICT keeps it safe under
  // idempotent import replay.
  await sql`
    INSERT INTO memory_media (memory_id, position, media_type, scan_status)
    SELECT ${memoryId}, gs, ${mediaType}, 'pending'
    FROM generate_series(0, ${count - 1}) AS gs
    ON CONFLICT (memory_id, position) DO NOTHING
  `;
}

/** All media for a memory, ordered hero-first. */
export async function listMediaByMemory(memoryId: string): Promise<MemoryMediaRow[]> {
  const rows = await sql`
    SELECT * FROM memory_media
    WHERE memory_id = ${memoryId}
    ORDER BY position ASC
  `;
  return rows as unknown as MemoryMediaRow[];
}

/**
 * Record a successful upload for one slot: set its media_key and flip scan_status → clear.
 * Upserts so live drops (which don't pre-create slots) and out-of-band positions still work.
 */
export async function setMediaAfterUpload(
  memoryId: string,
  position: number,
  mediaKey: string,
  mediaType: "photo" | "video" = "photo",
): Promise<void> {
  await sql`
    INSERT INTO memory_media (memory_id, position, media_type, media_key, scan_status)
    VALUES (${memoryId}, ${position}, ${mediaType}, ${mediaKey}, 'clear')
    ON CONFLICT (memory_id, position)
    DO UPDATE SET media_key = EXCLUDED.media_key, scan_status = 'clear'
  `;
}

/** Set a slot's thumbnail_key after server-side thumbnailing (post-clear, best-effort). */
export async function setMediaThumbnail(
  memoryId: string,
  position: number,
  thumbnailKey: string,
): Promise<void> {
  await sql`
    UPDATE memory_media
    SET thumbnail_key = ${thumbnailKey}
    WHERE memory_id = ${memoryId} AND position = ${position}
  `;
}
