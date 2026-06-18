// Import idempotency store (migration 0009_imports.sql).
// POST /v1/memories/import caches its response here keyed by (user_id, idempotency_key)
// so retries return the original result without creating duplicate memories.

import { sql } from "./client.js";

export interface ImportResultItem {
  cluster_index: number;
  memory_id: string;
  upload: { signed_put_url: string; expires_at: string } | null;
}

export interface ImportRecord {
  id: string;
  import_id: string;
  result: ImportResultItem[];
}

/** Store the result of a successful import. */
export async function storeImportResult(
  userId: string,
  idempotencyKey: string,
  importId: string,
  memories: ImportResultItem[],
): Promise<void> {
  await sql`
    INSERT INTO imports (id, user_id, idempotency_key, result_json)
    VALUES (${importId}, ${userId}, ${idempotencyKey}, ${JSON.stringify({ import_id: importId, memories })})
    ON CONFLICT (user_id, idempotency_key) DO NOTHING
  `;
}

/** Look up a prior import by idempotency key. Returns null if not found. */
export async function findImportByKey(
  userId: string,
  idempotencyKey: string,
): Promise<{ import_id: string; memories: ImportResultItem[] } | null> {
  const rows = await sql`
    SELECT result_json FROM imports
    WHERE user_id = ${userId} AND idempotency_key = ${idempotencyKey}
    LIMIT 1
  `;
  if (rows.length === 0) return null;
  return (rows[0] as { result_json: unknown }).result_json as { import_id: string; memories: ImportResultItem[] };
}
