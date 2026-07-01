import type { NextRequest } from "next/server";
import {
  checkDashboardSecret,
  dashboardWriteBlockedReason,
} from "./dashboardAuth";
import {
  pinClientIp,
  pinLockoutStatus,
  recordPinFailure,
  recordPinSuccess,
} from "./pinRateLimit";

export type DashboardWriteAuth =
  | { ok: true }
  | { ok: false; status: number; error: string; retryAfterS?: number };

/** Shared guard for PIN-gated dashboard writes (SEC-P4-2). */
export function authorizeDashboardWrite(
  request: NextRequest,
  bodySecret?: string,
): DashboardWriteAuth {
  const blocked = dashboardWriteBlockedReason();
  if (blocked) return { ok: false, status: 503, error: blocked };

  const ip = pinClientIp(request);
  const lockout = pinLockoutStatus(ip);
  if (lockout.locked) {
    return {
      ok: false,
      status: 429,
      error: "Too many failed PIN attempts. Try again later.",
      retryAfterS: lockout.retryAfterS,
    };
  }

  if (!checkDashboardSecret(request, bodySecret)) {
    recordPinFailure(ip);
    return { ok: false, status: 401, error: "Invalid secret" };
  }

  recordPinSuccess(ip);
  return { ok: true };
}
