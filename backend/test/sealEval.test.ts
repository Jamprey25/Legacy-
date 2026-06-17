// Seal evaluation (endpoint-unlock-seal-eval, location-ci-tests).
// Table-driven coverage of all 5 seal types at a fixed `now` for determinism.

import { describe, it, expect } from "vitest";
import { evaluateSeal } from "../src/lib/sealEval.js";

const NOW = new Date("2026-06-17T12:00:00Z");
const CREATED = new Date("2026-06-01T00:00:00Z");

describe("evaluateSeal", () => {
  it("none → always open", () => {
    expect(evaluateSeal("none", {}, CREATED, NOW).open).toBe(true);
  });

  describe("fixed_date", () => {
    it("open once open_at has passed", () => {
      expect(evaluateSeal("fixed_date", { open_at: "2026-06-01T00:00:00Z" }, CREATED, NOW).open).toBe(true);
    });
    it("closed before open_at, reports opensAt", () => {
      const r = evaluateSeal("fixed_date", { open_at: "2030-01-01T00:00:00Z" }, CREATED, NOW);
      expect(r.open).toBe(false);
      expect(r.opensAt).toBe(new Date("2030-01-01T00:00:00Z").toISOString());
    });
  });

  describe("duration", () => {
    it("open after locked_hours since created_at", () => {
      // created 2026-06-01, +24h = 2026-06-02, well before NOW
      expect(evaluateSeal("duration", { locked_hours: 24 }, CREATED, NOW).open).toBe(true);
    });
    it("closed while still within the locked window", () => {
      const created = new Date("2026-06-17T00:00:00Z"); // 12h before NOW
      const r = evaluateSeal("duration", { locked_hours: 48 }, created, NOW);
      expect(r.open).toBe(false);
    });
  });

  describe("age_based", () => {
    it("open once recipient reaches open_at_age", () => {
      // born 2000 → 26 in 2026 ≥ 18
      expect(evaluateSeal("age_based", { recipient_dob: "2000-01-01", open_at_age: 18 }, CREATED, NOW).open).toBe(true);
    });
    it("closed before the recipient is old enough", () => {
      const r = evaluateSeal("age_based", { recipient_dob: "2015-01-01", open_at_age: 18 }, CREATED, NOW);
      expect(r.open).toBe(false);
      expect(r.opensWhen).toBe("age_based");
    });
    it("closed (not crash) when config is incomplete", () => {
      expect(evaluateSeal("age_based", {}, CREATED, NOW).open).toBe(false);
    });
  });

  describe("recurring", () => {
    it("open during the yearly window", () => {
      // window 06-01 for 168h (7 days) → covers NOW (06-17)? 06-01..06-08 only. So closed.
      const closed = evaluateSeal("recurring", { window_start: "06-01", window_duration_hours: 168 }, CREATED, NOW);
      expect(closed.open).toBe(false);
      // widen window to 30 days → covers 06-17
      const open = evaluateSeal("recurring", { window_start: "06-01", window_duration_hours: 24 * 30 }, CREATED, NOW);
      expect(open.open).toBe(true);
    });
    it("closed outside the window reports next year's opensAt", () => {
      const r = evaluateSeal("recurring", { window_start: "12-01", window_duration_hours: 168 }, CREATED, NOW);
      expect(r.open).toBe(false);
      expect(r.opensAt).toBeDefined();
    });
  });
});
