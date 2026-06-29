import type { NextRequest } from "next/server";

function normalizeSecret(value: string | null | undefined): string {
  return (value ?? "").trim();
}

/** Shared PIN for dashboard writes (decisions + manual QA toggles). */
export function checkDashboardSecret(request: NextRequest, bodySecret?: string): boolean {
  const expected = normalizeSecret(process.env.DECISIONS_SECRET);
  if (!expected) return true;
  const provided = normalizeSecret(
    request.headers.get("x-decisions-secret") ?? bodySecret ?? ""
  );
  return provided.length > 0 && provided === expected;
}

export function isDashboardPinRequired(): boolean {
  return normalizeSecret(process.env.DECISIONS_SECRET).length > 0;
}

export const DASHBOARD_SECRET_HEADER = "x-decisions-secret";
export const DASHBOARD_SECRET_STORAGE_KEY = "legacy-dashboard-secret";

/** Client-side helpers (safe to import from "use client" components). */
export function getStoredDashboardSecret(): string {
  if (typeof window === "undefined") return "";
  return normalizeSecret(sessionStorage.getItem(DASHBOARD_SECRET_STORAGE_KEY));
}

export function setStoredDashboardSecret(secret: string): void {
  if (typeof window === "undefined") return;
  sessionStorage.setItem(DASHBOARD_SECRET_STORAGE_KEY, normalizeSecret(secret));
}

export function clearStoredDashboardSecret(): void {
  if (typeof window === "undefined") return;
  sessionStorage.removeItem(DASHBOARD_SECRET_STORAGE_KEY);
}
