// Presence pings: ephemeral proximity state for dwell-check and co-presence conditions.
// UNLOGGED table (no WAL) purged every ~3 minutes — never stores coordinates.

import { sql } from "./client.js";

export interface PresencePingRow {
  memory_id: string;
  user_id: string;
  last_seen_at: Date;
}

/** Upsert a presence ping. Called on every successful proximity check (scan + unlock). */
export async function upsertPresencePing(memoryId: string, userId: string): Promise<void> {
  await sql`
    INSERT INTO presence_pings (memory_id, user_id, last_seen_at)
    VALUES (${memoryId}, ${userId}, now())
    ON CONFLICT (memory_id, user_id)
    DO UPDATE SET last_seen_at = now()
  `;
}

/** Fetch the most recent ping for a (memory, user) pair. */
export async function getPresencePing(
  memoryId: string,
  userId: string,
): Promise<PresencePingRow | null> {
  const rows = await sql`
    SELECT * FROM presence_pings
    WHERE memory_id = ${memoryId} AND user_id = ${userId}
    LIMIT 1
  `;
  const row = rows[0] as PresencePingRow | undefined;
  return row ?? null;
}

/** Count distinct active users at a memory within the given window (for co_presence). */
export async function countActivePings(memoryId: string, windowMinutes: number): Promise<number> {
  const rows = await sql`
    SELECT COUNT(DISTINCT user_id) AS count
    FROM presence_pings
    WHERE memory_id = ${memoryId}
      AND last_seen_at > now() - (${windowMinutes} || ' minutes')::interval
  `;
  const row = rows[0] as { count: string } | undefined;
  return parseInt(row?.count ?? "0", 10);
}
