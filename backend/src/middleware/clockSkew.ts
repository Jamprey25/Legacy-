// Clock skew enforcement (api-contract §1.1, SEC-P5-3).

import type { Context, Next } from "hono";
import { ApiError } from "../lib/errors.js";

const SKEW_MS = 5 * 60_000;

/** Reject requests whose X-Request-Timestamp is outside the allowed clock skew.
 *  Required on all mutating routes except internal webhooks. */
export async function clockSkew(c: Context, next: Next): Promise<void> {
  const path = new URL(c.req.url).pathname;
  const exempt =
    path === "/v1/health" ||
    path.startsWith("/v1/internal/webhook");

  const ts = c.req.header("X-Request-Timestamp");
  if (!ts) {
    if (!exempt) {
      throw new ApiError("clock_skew", "Missing X-Request-Timestamp header.");
    }
    await next();
    return;
  }

  const t = Date.parse(ts);
  if (Number.isNaN(t) || Math.abs(Date.now() - t) > SKEW_MS) {
    throw new ApiError("clock_skew", "Your device clock is out of sync.");
  }
  await next();
}
