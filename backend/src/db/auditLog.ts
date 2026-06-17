// Append-only audit log writer.
//
// INVARIANT (enforced by the CI privacy gate): metadata MUST NOT contain latitude,
// longitude, or geohash — ever. IP is allowed; coordinates are not. Callers pass
// only non-locational facts (memory_id, result, method, counts).

import { sql } from "./client.js";

export interface AuditEvent {
  event: string; // e.g. "auth.login", "memory.drop", "scan", "unlock", "attest.bypass"
  actorId?: string | null;
  requestId?: string | null;
  ip?: string | null;
  metadata?: Record<string, unknown>;
}

/**
 * Insert one audit row. Throws on DB error — callers should use the fire-and-forget
 * `audit()` wrapper in lib/audit.ts so instrumentation never breaks the request path.
 */
export async function writeAuditEvent(e: AuditEvent): Promise<void> {
  await sql`
    INSERT INTO audit_log (event, actor_id, request_id, ip, metadata)
    VALUES (
      ${e.event},
      ${e.actorId ?? null},
      ${e.requestId ?? null},
      ${e.ip ?? null},
      ${JSON.stringify(e.metadata ?? {})}::jsonb
    )
  `;
}
