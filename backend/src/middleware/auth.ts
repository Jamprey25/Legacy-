// Request middleware:
//  - requestId: stamp every request for the error envelope + audit log.
//  - clockSkew: enforce X-Request-Timestamp within ±5 min (contract §1.1).
//  - requireAuth: validate the bearer session JWT and attach the user to context.

import type { Context, Next } from "hono";
import { ApiError } from "../lib/errors.js";
import { verifySession, type SessionClaims } from "../lib/jwt.js";

const SKEW_MS = 5 * 60_000;

export interface AuthVars {
  requestId: string;
  userId: string;
  ageTier: "adult" | "minor";
}

/** Stamp a request id (echoed in every error + used for audit). */
export async function requestId(c: Context, next: Next): Promise<void> {
  const id = c.req.header("X-Request-Id") ?? `req_${crypto.randomUUID()}`;
  c.set("requestId", id);
  await next();
}

/** Reject requests whose X-Request-Timestamp is outside the allowed clock skew. */
export async function clockSkew(c: Context, next: Next): Promise<void> {
  const ts = c.req.header("X-Request-Timestamp");
  if (ts) {
    const t = Date.parse(ts);
    if (Number.isNaN(t) || Math.abs(Date.now() - t) > SKEW_MS) {
      throw new ApiError("clock_skew", "Your device clock is out of sync.");
    }
  }
  await next();
}

/** Require a valid bearer session. Attaches userId + ageTier to context. */
export async function requireAuth(c: Context, next: Next): Promise<void> {
  const header = c.req.header("Authorization");
  const token = header?.startsWith("Bearer ") ? header.slice(7) : null;
  if (!token) throw new ApiError("unauthorized", "Sign in to continue.");

  const claims: SessionClaims = await verifySession(token);
  c.set("userId", claims.sub);
  c.set("ageTier", claims.age_tier);
  await next();
}
