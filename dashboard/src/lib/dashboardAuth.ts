import type { NextRequest } from "next/server";

function normalizeSecret(value: string | null | undefined): string {
  return (value ?? "").trim();
}

/** True when the dashboard can commit writes to tasks.json (GitHub Contents API). */
export function isGitHubWriteEnabled(): boolean {
  return normalizeSecret(process.env.GITHUB_TOKEN).length > 0;
}

/**
 * Shared PIN for dashboard writes (decisions + manual QA toggles).
 * Fail closed when GitHub writes are enabled but DECISIONS_SECRET is missing.
 */
export function checkDashboardSecret(request: NextRequest, bodySecret?: string): boolean {
  const expected = normalizeSecret(process.env.DECISIONS_SECRET);
  if (isGitHubWriteEnabled() && !expected) return false;
  if (!expected) return true;
  const provided = normalizeSecret(
    request.headers.get("x-decisions-secret") ?? bodySecret ?? ""
  );
  return provided.length > 0 && provided === expected;
}

export function isDashboardPinRequired(): boolean {
  return isGitHubWriteEnabled() || normalizeSecret(process.env.DECISIONS_SECRET).length > 0;
}

/** Returns an error message when write APIs must reject (misconfigured prod). */
export function dashboardWriteBlockedReason(): string | null {
  if (isGitHubWriteEnabled() && !normalizeSecret(process.env.DECISIONS_SECRET)) {
    return "Dashboard write PIN (DECISIONS_SECRET) is required when GITHUB_TOKEN is set.";
  }
  return null;
}

export const DASHBOARD_SECRET_HEADER = "x-decisions-secret";
export const DASHBOARD_SECRET_STORAGE_KEY = "legacy-dashboard-secret";

/** Allowed authors for discussion thread replies (SEC-P4-3). */
export const VALID_THREAD_AUTHORS = new Set(["ios", "backend", "joseph"]);

/** Max reply body size before GitHub write (SEC-P4-4). */
export const MAX_REPLY_TEXT_BYTES = 16 * 1024;

export function isValidThreadAuthor(author: string): author is "ios" | "backend" | "joseph" {
  return VALID_THREAD_AUTHORS.has(author);
}

export function replyTextTooLarge(text: string): boolean {
  return new TextEncoder().encode(text).byteLength > MAX_REPLY_TEXT_BYTES;
}

/** Require PIN on read routes when writes are PIN-gated (SEC-P4-1). */
export function authorizeDashboardRead(request: NextRequest): { ok: true } | { ok: false; status: number; error: string } {
  if (!isDashboardPinRequired()) return { ok: true };
  if (!checkDashboardSecret(request)) {
    return { ok: false, status: 401, error: "Dashboard PIN required." };
  }
  return { ok: true };
}

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
