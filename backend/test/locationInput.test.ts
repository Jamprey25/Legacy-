// Location input validation (DEC-23 accuracy sanity). Pure function, no DB.
// The accuracy bound (> 0 and < 1000) is an anti-spoofing boundary, so it gets
// explicit coverage — including the exact-1000 edge that was previously inconsistent.

import { describe, it, expect } from "vitest";
import { validateLocationInput } from "../src/lib/locationInput.js";
import { ApiError } from "../src/lib/errors.js";

describe("validateLocationInput", () => {
  it("accepts a valid fix", () => {
    expect(validateLocationInput(37.7749, -122.4194, 8)).toEqual({
      lat: 37.7749,
      lng: -122.4194,
      accuracyM: 8,
    });
  });

  it("rejects non-numeric coordinates", () => {
    expect(() => validateLocationInput("37", -122, 8)).toThrow(ApiError);
    expect(() => validateLocationInput(37, null, 8)).toThrow(ApiError);
  });

  it("rejects out-of-range coordinates", () => {
    expect(() => validateLocationInput(91, 0, 8)).toThrow(ApiError);
    expect(() => validateLocationInput(0, 181, 8)).toThrow(ApiError);
    expect(() => validateLocationInput(-91, 0, 8)).toThrow(ApiError);
  });

  it("rejects accuracy <= 0", () => {
    expect(() => validateLocationInput(0, 0, 0)).toThrow(ApiError);
    expect(() => validateLocationInput(0, 0, -5)).toThrow(ApiError);
  });

  it("rejects accuracy >= 1000 (including exactly 1000)", () => {
    expect(() => validateLocationInput(0, 0, 1000)).toThrow(ApiError);
    expect(() => validateLocationInput(0, 0, 1500)).toThrow(ApiError);
  });

  it("accepts accuracy just under the ceiling", () => {
    expect(validateLocationInput(0, 0, 999.9).accuracyM).toBe(999.9);
  });
});
