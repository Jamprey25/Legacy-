import { describe, it, expect } from "vitest";
import { encode, distanceMetres } from "../src/lib/geohash.js";

describe("encode", () => {
  it("produces the expected hash for a known location (San Francisco)", () => {
    // 9q8yy = precision 5 prefix for SF; precision 9 starts with 9q8yy9...
    const hash = encode(37.7749, -122.4194, 9);
    expect(hash).toHaveLength(9);
    expect(hash.startsWith("9q8yy")).toBe(true);
  });

  it("produces precision-5 coarse zone from left(precision-9, 5)", () => {
    const full = encode(37.7749, -122.4194, 9);
    expect(full.slice(0, 5)).toBe(encode(37.7749, -122.4194, 5));
  });

  it("handles the prime meridian (lng = 0)", () => {
    const h = encode(51.5074, 0, 9);
    expect(h).toHaveLength(9);
  });

  it("handles extreme coordinates", () => {
    expect(encode(90, 180, 9)).toHaveLength(9);
    expect(encode(-90, -180, 9)).toHaveLength(9);
  });
});

describe("distanceMetres", () => {
  it("returns 0 for identical points", () => {
    expect(distanceMetres(0, 0, 0, 0)).toBe(0);
  });

  it("returns ~111km for 1° latitude difference at the equator", () => {
    const d = distanceMetres(0, 0, 1, 0);
    expect(d).toBeGreaterThan(110_000);
    expect(d).toBeLessThan(112_000);
  });

  it("correctly measures a short urban distance (~250m)", () => {
    // Market St SF → Civic Center ~250m
    const d = distanceMetres(37.7749, -122.4194, 37.7773, -122.4194);
    expect(d).toBeGreaterThan(200);
    expect(d).toBeLessThan(320);
  });
});
