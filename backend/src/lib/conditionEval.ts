// Condition evaluation (api-contract.md §6, tasks endpoint-unlock-condition-eval).
// All evaluation server-side at unlock time. Fallback timestamp is always set (DB NOT NULL).

export type ConditionType =
  | "time_of_day"
  | "season"
  | "weather"
  | "co_presence"
  | "long_absence"
  | "nth_return";

export interface ConditionConfig {
  // time_of_day
  after_hour?: number;
  before_hour?: number;
  // season
  month_start?: number;
  month_end?: number;
  // weather
  condition?: string; // "rainy" | "sunny" | "snow"
  // co_presence
  required_users?: number;
  window_minutes?: number;
  // long_absence
  days_since_last_find?: number;
  // nth_return
  n?: number;
}

export interface ConditionResult {
  met: boolean;
  fallbackAt: string; // always present — caller uses for 423 condition_unmet body
}

export interface ConditionContext {
  /** For time_of_day: current UTC hour (0-23). Use timezone of drop point if available. */
  currentHour: number;
  /** For season: current UTC month (1-12). */
  currentMonth: number;
  /** For weather: current cached condition at the geohash zone (may be null if not yet fetched). */
  weatherCondition?: string | null;
  /** For co_presence: count of distinct active pings at the memory. */
  activePingCount?: number;
  /** For long_absence: days since the user last found this memory (null = never found). */
  daysSinceLastFind?: number | null;
  /** For nth_return: how many times the user has found this memory (including current attempt). */
  returnCount?: number;
  /** ISO fallback timestamp from conditions table. */
  fallbackAt: string;
  now: Date;
}

export function evaluateCondition(
  conditionType: ConditionType,
  config: ConditionConfig,
  ctx: ConditionContext,
): ConditionResult {
  const fallback = { met: false, fallbackAt: ctx.fallbackAt };

  // If fallback time has already passed, condition is auto-satisfied.
  if (new Date(ctx.fallbackAt) <= ctx.now) return { met: true, fallbackAt: ctx.fallbackAt };

  switch (conditionType) {
    case "time_of_day": {
      const { after_hour = 0, before_hour = 23 } = config;
      const h = ctx.currentHour;
      const met =
        after_hour <= before_hour
          ? h >= after_hour && h < before_hour
          : h >= after_hour || h < before_hour; // spans midnight
      return met ? { met: true, fallbackAt: ctx.fallbackAt } : fallback;
    }

    case "season": {
      const { month_start = 1, month_end = 12 } = config;
      const m = ctx.currentMonth;
      const met =
        month_start <= month_end
          ? m >= month_start && m <= month_end
          : m >= month_start || m <= month_end; // spans year boundary (e.g. Dec–Feb)
      return met ? { met: true, fallbackAt: ctx.fallbackAt } : fallback;
    }

    case "weather": {
      if (!ctx.weatherCondition) return fallback; // not yet fetched → not met
      const met = ctx.weatherCondition === config.condition;
      return met ? { met: true, fallbackAt: ctx.fallbackAt } : fallback;
    }

    case "co_presence": {
      const required = config.required_users ?? 2;
      const met = (ctx.activePingCount ?? 0) >= required;
      return met ? { met: true, fallbackAt: ctx.fallbackAt } : fallback;
    }

    case "long_absence": {
      const threshold = config.days_since_last_find ?? 365;
      if (ctx.daysSinceLastFind === null || ctx.daysSinceLastFind === undefined) {
        return fallback; // never found — absence not yet measured
      }
      const met = ctx.daysSinceLastFind >= threshold;
      return met ? { met: true, fallbackAt: ctx.fallbackAt } : fallback;
    }

    case "nth_return": {
      const n = config.n ?? 1;
      const met = (ctx.returnCount ?? 0) >= n;
      return met ? { met: true, fallbackAt: ctx.fallbackAt } : fallback;
    }

    default:
      return { met: true, fallbackAt: ctx.fallbackAt };
  }
}
