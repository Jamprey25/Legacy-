// Condition evaluation (endpoint-unlock-condition-eval, location-ci-tests).
// Table-driven coverage of all 6 condition types + the fallback auto-satisfy rule.

import { describe, it, expect } from "vitest";
import { evaluateCondition, type ConditionContext } from "../src/lib/conditionEval.js";

const NOW = new Date("2026-06-17T12:00:00Z");
const FUTURE_FALLBACK = "2030-01-01T00:00:00Z"; // not yet reached → condition must be met on its own
const PAST_FALLBACK = "2020-01-01T00:00:00Z"; // already passed → auto-satisfied

function ctx(overrides: Partial<ConditionContext> = {}): ConditionContext {
  return {
    currentHour: NOW.getUTCHours(),
    currentMonth: NOW.getUTCMonth() + 1,
    fallbackAt: FUTURE_FALLBACK,
    now: NOW,
    ...overrides,
  };
}

describe("fallback auto-satisfy", () => {
  it("any condition is met once its fallback time has passed", () => {
    const r = evaluateCondition("weather", { condition: "snow" }, ctx({ fallbackAt: PAST_FALLBACK }));
    expect(r.met).toBe(true);
  });
});

describe("time_of_day", () => {
  it("met inside the window", () => {
    expect(evaluateCondition("time_of_day", { after_hour: 8, before_hour: 18 }, ctx({ currentHour: 12 })).met).toBe(true);
  });
  it("not met outside the window", () => {
    expect(evaluateCondition("time_of_day", { after_hour: 18, before_hour: 23 }, ctx({ currentHour: 12 })).met).toBe(false);
  });
  it("handles windows that span midnight", () => {
    // 22:00–06:00 → 02:00 is inside
    expect(evaluateCondition("time_of_day", { after_hour: 22, before_hour: 6 }, ctx({ currentHour: 2 })).met).toBe(true);
    expect(evaluateCondition("time_of_day", { after_hour: 22, before_hour: 6 }, ctx({ currentHour: 12 })).met).toBe(false);
  });
});

describe("season", () => {
  it("met within month range", () => {
    expect(evaluateCondition("season", { month_start: 6, month_end: 8 }, ctx({ currentMonth: 6 })).met).toBe(true);
  });
  it("handles ranges spanning the year boundary (Dec–Feb)", () => {
    expect(evaluateCondition("season", { month_start: 12, month_end: 2 }, ctx({ currentMonth: 1 })).met).toBe(true);
    expect(evaluateCondition("season", { month_start: 12, month_end: 2 }, ctx({ currentMonth: 6 })).met).toBe(false);
  });
});

describe("weather", () => {
  it("met when cached condition matches", () => {
    expect(evaluateCondition("weather", { condition: "rainy" }, ctx({ weatherCondition: "rainy" })).met).toBe(true);
  });
  it("not met when condition differs or is unknown", () => {
    expect(evaluateCondition("weather", { condition: "rainy" }, ctx({ weatherCondition: "sunny" })).met).toBe(false);
    expect(evaluateCondition("weather", { condition: "rainy" }, ctx({ weatherCondition: null })).met).toBe(false);
  });
});

describe("co_presence", () => {
  it("met when enough distinct users are present", () => {
    expect(evaluateCondition("co_presence", { required_users: 3 }, ctx({ activePingCount: 3 })).met).toBe(true);
  });
  it("not met below the threshold", () => {
    expect(evaluateCondition("co_presence", { required_users: 3 }, ctx({ activePingCount: 2 })).met).toBe(false);
  });
});

describe("long_absence", () => {
  it("met once days since last find passes the threshold", () => {
    expect(evaluateCondition("long_absence", { days_since_last_find: 365 }, ctx({ daysSinceLastFind: 400 })).met).toBe(true);
  });
  it("not met when recently found", () => {
    expect(evaluateCondition("long_absence", { days_since_last_find: 365 }, ctx({ daysSinceLastFind: 10 })).met).toBe(false);
  });
  it("not met when never found (absence not yet measurable)", () => {
    expect(evaluateCondition("long_absence", { days_since_last_find: 365 }, ctx({ daysSinceLastFind: null })).met).toBe(false);
  });
});

describe("nth_return", () => {
  it("met on the nth visit", () => {
    expect(evaluateCondition("nth_return", { n: 3 }, ctx({ returnCount: 3 })).met).toBe(true);
  });
  it("not met before the nth visit", () => {
    expect(evaluateCondition("nth_return", { n: 3 }, ctx({ returnCount: 2 })).met).toBe(false);
  });
});
