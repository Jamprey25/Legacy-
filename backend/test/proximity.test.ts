// Proximity bubble math (endpoint-scan-bubble-math, location-ci-tests).
// Table-driven coverage of the asymmetric bubbles + warmth bands, plus geographic
// scenarios (approach, drive-by, urban canyon) built from real lat/lng offsets.
//
// Pure-function tests — no DB. The dwell rule (two checks ≥20s apart) that defeats a
// drive-by lives in the unlock route, not here; these assert the per-fix snapshot only.

import { describe, it, expect } from "vitest";
import { ownMemoryProximity, othersMemoryProximity, type WarmthBand } from "../src/lib/proximity.js";

// Base point (San Francisco). ~111,320 m per degree latitude.
const BASE_LAT = 37.7749;
const BASE_LNG = -122.4194;
const M_PER_DEG_LAT = 111_320;

/** A point `metres` due north of base — distanceMetres back to base ≈ metres. */
function north(metres: number): { lat: number; lng: number } {
  return { lat: BASE_LAT + metres / M_PER_DEG_LAT, lng: BASE_LNG };
}

describe("ownMemoryProximity — bubble = 25m + min(accuracy,75m)", () => {
  // accuracy 10 → radius 35m; approaching ≤ 105m
  const cases: Array<{ name: string; metres: number; accuracy: number; inBubble: boolean; warmth: WarmthBand }> = [
    { name: "on top of pin", metres: 0, accuracy: 10, inBubble: true, warmth: "in_bubble" },
    { name: "just inside radius", metres: 34, accuracy: 10, inBubble: true, warmth: "in_bubble" },
    { name: "just outside radius → approaching", metres: 40, accuracy: 10, inBubble: false, warmth: "approaching" },
    { name: "edge of approaching band", metres: 100, accuracy: 10, inBubble: false, warmth: "approaching" },
    { name: "beyond approaching → coarse", metres: 200, accuracy: 10, inBubble: false, warmth: "coarse" },
    { name: "poor accuracy widens bubble (cap 75)", metres: 90, accuracy: 200, inBubble: true, warmth: "in_bubble" },
  ];

  for (const c of cases) {
    it(c.name, () => {
      const p = north(c.metres);
      const r = ownMemoryProximity(p.lat, p.lng, c.accuracy, BASE_LAT, BASE_LNG);
      expect(r.inBubble).toBe(c.inBubble);
      expect(r.warmth).toBe(c.warmth);
    });
  }
});

describe("othersMemoryProximity — bubble = 20m + min(accuracy,25m), reject if accuracy > 50m", () => {
  it("returns null when accuracy > 50m (silent reject, DEC-15)", () => {
    const p = north(5);
    expect(othersMemoryProximity(p.lat, p.lng, 51, BASE_LAT, BASE_LNG)).toBeNull();
  });

  it("tighter bubble than own — 30m out with accuracy 10 is NOT in bubble", () => {
    // radius = 20 + 10 = 30m; 30m is on the boundary (<=), test just outside
    const p = north(35);
    const r = othersMemoryProximity(p.lat, p.lng, 10, BASE_LAT, BASE_LNG);
    expect(r).not.toBeNull();
    expect(r!.inBubble).toBe(false);
    expect(r!.warmth).toBe("approaching");
  });

  it("inside the tight bubble unlocks", () => {
    const p = north(15);
    const r = othersMemoryProximity(p.lat, p.lng, 10, BASE_LAT, BASE_LNG);
    expect(r!.inBubble).toBe(true);
    expect(r!.warmth).toBe("in_bubble");
  });

  it("accuracy cap at 25 — radius never exceeds 45m even with accuracy 50", () => {
    const justOut = north(46);
    expect(othersMemoryProximity(justOut.lat, justOut.lng, 50, BASE_LAT, BASE_LNG)!.inBubble).toBe(false);
    const justIn = north(44);
    expect(othersMemoryProximity(justIn.lat, justIn.lng, 50, BASE_LAT, BASE_LNG)!.inBubble).toBe(true);
  });
});

describe("scenario: approach — warmth escalates coarse → approaching → in_bubble", () => {
  it("walks in toward an own memory", () => {
    const accuracy = 10; // radius 35m, approaching ≤ 105m
    const bands = [500, 150, 80, 10].map((m) => {
      const p = north(m);
      return ownMemoryProximity(p.lat, p.lng, accuracy, BASE_LAT, BASE_LNG).warmth;
    });
    expect(bands).toEqual(["coarse", "coarse", "approaching", "in_bubble"]);
  });
});

describe("scenario: urban canyon — degraded accuracy still excludes others' memories", () => {
  it("accuracy 60m → others' memory silently excluded even when physically close", () => {
    const p = north(5);
    expect(othersMemoryProximity(p.lat, p.lng, 60, BASE_LAT, BASE_LNG)).toBeNull();
  });

  it("same degraded fix still resolves own memory (generous bubble)", () => {
    const p = north(5);
    const r = ownMemoryProximity(p.lat, p.lng, 60, BASE_LAT, BASE_LNG);
    expect(r.inBubble).toBe(true);
  });
});

describe("scenario: drive-by — closest fix may be in-bubble (dwell defeats it at route layer)", () => {
  it("a single fast pass shows in_bubble at closest point", () => {
    // 0m closest approach with good accuracy → in_bubble; dwell (not tested here) blocks unlock.
    const p = north(0);
    expect(ownMemoryProximity(p.lat, p.lng, 8, BASE_LAT, BASE_LNG).inBubble).toBe(true);
  });
});
