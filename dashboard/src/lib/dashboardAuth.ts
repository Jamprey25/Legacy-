import type { NextRequest } from "next/server";

/** Shared PIN for dashboard writes (decisions + manual QA toggles). */
export function checkDashboardSecret(request: NextRequest, bodySecret?: string): boolean {
  const expected = process.env.DECISIONS_SECRET;
  if (!expected) return true;
  const provided =
    request.headers.get("x-decisions-secret") ??
    bodySecret ??
    "";
  return provided === expected;
}

export const DASHBOARD_SECRET_HEADER = "x-decisions-secret";
export const DASHBOARD_SECRET_STORAGE_KEY = "legacy-dashboard-secret";
