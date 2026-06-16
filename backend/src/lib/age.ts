// Age gate. Under-13 is rejected outright; 13–15 is a restricted "minor" tier
// (no public content, parental-consent flow in Phase 2); 16+ is "adult".

import { ApiError } from "./errors.js";

export type AgeTier = "adult" | "minor";

/** Whole years between dob and `now` (default today). */
export function ageInYears(dob: Date, now: Date = new Date()): number {
  let age = now.getUTCFullYear() - dob.getUTCFullYear();
  const m = now.getUTCMonth() - dob.getUTCMonth();
  if (m < 0 || (m === 0 && now.getUTCDate() < dob.getUTCDate())) age--;
  return age;
}

/**
 * Resolve the age tier from a DOB. Throws ApiError(age_restricted) for under-13 —
 * the account is never created. Throws invalid_request for an unparseable/future DOB.
 */
export function resolveAgeTier(dobISO: string, now: Date = new Date()): AgeTier {
  const dob = new Date(dobISO);
  if (Number.isNaN(dob.getTime()) || dob.getTime() > now.getTime()) {
    throw new ApiError("invalid_request", "Invalid date of birth.");
  }
  const age = ageInYears(dob, now);
  if (age < 13) {
    throw new ApiError("age_restricted", "You must be at least 13 to use Legacy.");
  }
  return age < 16 ? "minor" : "adult";
}
