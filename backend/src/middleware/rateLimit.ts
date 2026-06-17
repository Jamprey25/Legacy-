// Rate-limiting middleware factory (rate-limiting task).
//
// Fixed-window limiter keyed by IP (unauthenticated routes like /auth) or user id
// (authenticated routes). Backed by a Postgres counter so it's correct across
// concurrent Vercel Function instances — in-memory counters would not be.
//
// Usage:
//   authRoutes.use("*", rateLimit({ name: "auth", limit: 10, windowSec: 600, keyBy: "ip" }))
//   memoriesRoutes.post("/", rateLimit({ name: "drop", limit: 20, windowSec: 3600, keyBy: "user" }), handler)
//
// keyBy "user" must run AFTER requireAuth (needs c.get("userId")); falls back to IP
// if no userId is present, so it can never silently no-op.

import type { Context, Next } from "hono";
import { ApiError } from "../lib/errors.js";
import { incrementAndCount } from "../db/rateLimits.js";

export interface RateLimitOptions {
  /** Short label for the bucket key namespace, e.g. "auth", "scan", "unlock", "drop". */
  name: string;
  /** Max requests allowed per window. */
  limit: number;
  /** Window length in seconds. */
  windowSec: number;
  /** Key by client IP (unauthenticated) or authenticated user id. */
  keyBy: "ip" | "user";
}

/** Best-effort client IP from the proxy chain (Vercel sets x-forwarded-for). */
function clientIp(c: Context): string {
  const fwd = c.req.header("x-forwarded-for");
  if (fwd) return fwd.split(",")[0]!.trim();
  return c.req.header("x-real-ip") ?? "unknown";
}

/** Start of the current fixed window: floor(now / windowSec). */
function windowStart(windowSec: number, now: number): Date {
  const windowMs = windowSec * 1000;
  return new Date(Math.floor(now / windowMs) * windowMs);
}

export function rateLimit(opts: RateLimitOptions) {
  return async function rateLimitMiddleware(c: Context, next: Next): Promise<void> {
    const userId = c.get("userId") as string | undefined;
    const bucketKey =
      opts.keyBy === "user" && userId
        ? `${opts.name}:user:${userId}`
        : `${opts.name}:ip:${clientIp(c)}`;

    const start = windowStart(opts.windowSec, Date.now());

    let count: number;
    try {
      count = await incrementAndCount(bucketKey, start);
    } catch {
      // Fail-open: a counter store hiccup must not take down the endpoint.
      await next();
      return;
    }

    if (count > opts.limit) {
      const retryAfter = Math.ceil((start.getTime() + opts.windowSec * 1000 - Date.now()) / 1000);
      throw new ApiError("rate_limited", "Too many requests. Slow down.", 429, {
        retry_after_s: Math.max(retryAfter, 1),
      });
    }

    await next();
  };
}
