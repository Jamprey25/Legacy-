// Request middleware:
//  - requestId: stamp every request for the error envelope + audit log.
//  - requireAuth: validate the bearer session JWT and attach the user to context.

import type { Context, Next } from "hono";
import { ApiError } from "../lib/errors.js";
import { verifySession, type SessionClaims } from "../lib/jwt.js";
import { isSessionRevoked } from "../db/sessions.js";

export { clockSkew } from "./clockSkew.js";

export interface AuthVars {
  requestId: string;
  userId: string;
  deviceId: string | undefined;
  ageTier: "adult" | "minor";
}

/** Stamp a request id (echoed in every error + used for audit). */
export async function requestId(c: Context, next: Next): Promise<void> {
  const id = c.req.header("X-Request-Id") ?? `req_${crypto.randomUUID()}`;
  c.set("requestId", id);
  await next();
}

/** Require a valid bearer session. Attaches userId + deviceId + ageTier to context. */
export async function requireAuth(c: Context, next: Next): Promise<void> {
  const header = c.req.header("Authorization");
  const token = header?.startsWith("Bearer ") ? header.slice(7) : null;
  if (!token) throw new ApiError("unauthorized", "Sign in to continue.");

  const claims: SessionClaims = await verifySession(token);

  if (claims.did) {
    const revoked = await isSessionRevoked(claims.sub, claims.did);
    if (revoked) throw new ApiError("token_expired", "Your session has expired. Please sign in again.");
  }

  c.set("userId", claims.sub);
  c.set("deviceId", claims.did);
  c.set("ageTier", claims.age_tier);
  await next();
}
