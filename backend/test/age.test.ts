// Age-gate logic. Pure functions, no DB — the under-13 hard-reject is a legal boundary,
// so it gets explicit coverage. Uses a fixed "now" for determinism.

import { describe, it, expect } from "vitest";
import { ageInYears, resolveAgeTier } from "../src/lib/age.js";
import { ApiError } from "../src/lib/errors.js";

const NOW = new Date("2026-06-16T00:00:00Z");

describe("ageInYears", () => {
  it("counts whole years, not yet had birthday this year", () => {
    expect(ageInYears(new Date("2010-12-01"), NOW)).toBe(15);
  });
  it("counts the birthday itself", () => {
    expect(ageInYears(new Date("2010-06-16"), NOW)).toBe(16);
  });
});

describe("resolveAgeTier", () => {
  it("rejects under-13 with age_restricted", () => {
    try {
      resolveAgeTier("2014-06-17", NOW); // 11
      throw new Error("should have thrown");
    } catch (e) {
      expect(e).toBeInstanceOf(ApiError);
      expect((e as ApiError).code).toBe("age_restricted");
      expect((e as ApiError).status).toBe(403);
    }
  });

  it("classifies exactly 13 as minor", () => {
    expect(resolveAgeTier("2013-06-16", NOW)).toBe("minor");
  });

  it("classifies 13–15 as minor", () => {
    expect(resolveAgeTier("2011-01-01", NOW)).toBe("minor");
  });

  it("classifies exactly 16 as adult", () => {
    expect(resolveAgeTier("2010-06-16", NOW)).toBe("adult");
  });

  it("rejects a future DOB", () => {
    expect(() => resolveAgeTier("2030-01-01", NOW)).toThrow(ApiError);
  });

  it("rejects an unparseable DOB", () => {
    expect(() => resolveAgeTier("not-a-date", NOW)).toThrow(ApiError);
  });
});
