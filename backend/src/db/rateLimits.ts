// Rate-limit counters: fixed-window, Postgres-backed (correct across serverless instances).
// One atomic upsert per request returns the post-increment count for the current window.

import { sql } from "./client.js";

/**
 * Increment the counter for (bucketKey, windowStart) and return the new count.
 * Atomic — concurrent requests in the same window serialize on the PK row.
 */
export async function incrementAndCount(bucketKey: string, windowStart: Date): Promise<number> {
  const rows = await sql`
    INSERT INTO rate_limits (bucket_key, window_start, count)
    VALUES (${bucketKey}, ${windowStart.toISOString()}, 1)
    ON CONFLICT (bucket_key, window_start)
    DO UPDATE SET count = rate_limits.count + 1
    RETURNING count
  `;
  const row = rows[0] as { count: number } | undefined;
  return row?.count ?? 1;
}
