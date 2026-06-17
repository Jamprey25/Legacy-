// Fire-and-forget audit instrumentation. Reads request_id + IP from the Hono context
// and writes an audit row WITHOUT awaiting failure into the request path — a logging
// hiccup must never break auth, drop, scan, or unlock.
//
// PRIVACY: never pass coordinates in `metadata` (CI privacy gate enforces the table
// schema; this comment is the reminder at the call site).

import type { Context } from "hono";
import { writeAuditEvent } from "../db/auditLog.js";

/** Best-effort client IP from the proxy chain. */
function clientIp(c: Context): string | null {
  const fwd = c.req.header("x-forwarded-for");
  if (fwd) return fwd.split(",")[0]!.trim();
  return c.req.header("x-real-ip") ?? null;
}

/**
 * Record an audit event. Non-blocking and non-throwing: errors are swallowed so
 * instrumentation can never fail the request. `actorId` defaults to the authed user.
 */
export function audit(
  c: Context,
  event: string,
  metadata: Record<string, unknown> = {},
  actorId?: string | null,
): void {
  const resolvedActor = actorId ?? (c.get("userId") as string | undefined) ?? null;
  const requestId = (c.get("requestId") as string | undefined) ?? null;
  const ip = clientIp(c);

  void writeAuditEvent({ event, actorId: resolvedActor, requestId, ip, metadata }).catch((err) => {
    // Never throw from instrumentation; log to stderr for ops visibility.
    console.error(`[audit] failed to write ${event}:`, err);
  });
}
