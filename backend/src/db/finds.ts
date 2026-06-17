// Finds: durable record of each unlock. Drives nth_return count and long_absence condition.

import { sql } from "./client.js";

export interface FindRow {
  id: string;
  memory_id: string;
  user_id: string;
  found_at: Date;
}

/** Record a Find. */
export async function createFind(memoryId: string, userId: string): Promise<FindRow> {
  const rows = await sql`
    INSERT INTO finds (memory_id, user_id)
    VALUES (${memoryId}, ${userId})
    RETURNING *
  `;
  return rows[0] as unknown as FindRow;
}

/** Count how many times a user has found a specific memory. */
export async function getReturnCount(memoryId: string, userId: string): Promise<number> {
  const rows = await sql`
    SELECT COUNT(*) AS count FROM finds
    WHERE memory_id = ${memoryId} AND user_id = ${userId}
  `;
  const row = rows[0] as { count: string } | undefined;
  return parseInt(row?.count ?? "0", 10);
}

/** Get the last found_at for a (memory, user) pair. Null if never found. */
export async function getLastFoundAt(
  memoryId: string,
  userId: string,
): Promise<Date | null> {
  const rows = await sql`
    SELECT MAX(found_at) AS found_at FROM finds
    WHERE memory_id = ${memoryId} AND user_id = ${userId}
  `;
  const row = rows[0] as { found_at: Date | null } | undefined;
  return row?.found_at ?? null;
}
