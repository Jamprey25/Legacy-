// Shared location-input validation for all location-bearing endpoints
// (scan, unlock, drop). Enforces DEC-23 accuracy sanity: accuracy must be > 0
// and < 1000m. Timestamp clock-skew (±5min) is enforced globally by the
// clockSkew middleware, so it is not re-checked here.
//
// Coordinates are validated, used, and discarded — never persisted for non-owners
// and never logged (SEC-LOC-1). This function only validates shape/range.

import { ApiError } from "./errors.js";

export interface ValidatedLocation {
  lat: number;
  lng: number;
  accuracyM: number;
}

/**
 * Validate raw lat/lng/accuracy_m from a request body. Throws ApiError on bad input.
 * DEC-23: accuracy_m must be > 0 and < 1000 (rejects spoofed/garbage fixes).
 */
export function validateLocationInput(lat: unknown, lng: unknown, accuracyM: unknown): ValidatedLocation {
  if (typeof lat !== "number" || typeof lng !== "number") {
    throw new ApiError("invalid_coordinates", "lat and lng must be numbers.");
  }
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    throw new ApiError("invalid_coordinates", "Coordinates out of range.");
  }
  if (typeof accuracyM !== "number" || accuracyM <= 0 || accuracyM >= 1000) {
    throw new ApiError("invalid_coordinates", "accuracy_m must be > 0 and < 1000.");
  }
  return { lat, lng, accuracyM };
}
