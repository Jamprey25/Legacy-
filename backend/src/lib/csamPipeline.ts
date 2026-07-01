// CSAM / content-scan gating (SEC-P2-1).
//
// In production, stub pipeline must NOT flip scan_status → clear. Dev/staging may
// use CSAM_PIPELINE=stub for local iteration.

import { ApiError } from "./errors.js";

export function isProductionEnvironment(): boolean {
  const nodeEnv = process.env.NODE_ENV ?? "";
  const vercelEnv = process.env.VERCEL_ENV ?? "";
  return nodeEnv === "production" || vercelEnv === "production";
}

export function csamPipelineMode(): string {
  return process.env.CSAM_PIPELINE ?? "stub";
}

/** True when the dev-only auto-clear stub path is allowed. */
export function isDevStubPipeline(): boolean {
  return csamPipelineMode() === "stub" && !isProductionEnvironment();
}

/**
 * Throws when scan_status must not advance to clear (production + stub pipeline).
 * Call immediately before any code path that marks media or memories as clear.
 */
export function assertScanClearAllowed(): void {
  if (isProductionEnvironment() && csamPipelineMode() === "stub") {
    throw new ApiError("internal_error", "Content scanning is not configured.");
  }
}
