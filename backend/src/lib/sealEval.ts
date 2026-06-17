// Seal evaluation (api-contract.md §6, tasks endpoint-unlock-seal-eval).
// All evaluation happens server-side at unlock time. Client never evaluates seals.

export type SealType = "none" | "fixed_date" | "duration" | "age_based" | "recurring";

export interface SealConfig {
  // fixed_date
  open_at?: string;
  // duration
  locked_hours?: number;
  // age_based
  recipient_dob?: string;
  open_at_age?: number;
  // recurring
  window_start?: string; // "MM-DD"
  window_duration_hours?: number;
  next_open?: string;
}

export interface SealResult {
  open: boolean;
  opensAt?: string; // ISO string, for "sealed" 423 response
  opensWhen?: string; // e.g. "age_based"
}

/**
 * Evaluate whether a seal is currently open.
 * createdAt: the memory's created_at timestamp (needed for duration seal).
 */
export function evaluateSeal(
  sealType: SealType,
  config: SealConfig,
  createdAt: Date,
  now = new Date(),
): SealResult {
  switch (sealType) {
    case "none":
      return { open: true };

    case "fixed_date": {
      const openAt = new Date(config.open_at!);
      if (now >= openAt) return { open: true };
      return { open: false, opensAt: openAt.toISOString() };
    }

    case "duration": {
      const openAt = new Date(createdAt.getTime() + (config.locked_hours ?? 0) * 3_600_000);
      if (now >= openAt) return { open: true };
      return { open: false, opensAt: openAt.toISOString() };
    }

    case "age_based": {
      if (!config.recipient_dob || config.open_at_age === undefined) {
        return { open: false, opensWhen: "age_based" };
      }
      const dob = new Date(config.recipient_dob);
      const openAt = new Date(dob);
      openAt.setFullYear(openAt.getFullYear() + config.open_at_age);
      if (now >= openAt) return { open: true };
      return { open: false, opensWhen: "age_based" };
    }

    case "recurring": {
      // window_start is "MM-DD" e.g. "06-01"; window opens for window_duration_hours
      const parts = (config.window_start ?? "01-01").split("-").map(Number);
      const [month = 1, day = 1] = parts;
      const windowStart = new Date(Date.UTC(now.getUTCFullYear(), month - 1, day));
      const windowEnd = new Date(windowStart.getTime() + (config.window_duration_hours ?? 168) * 3_600_000);
      // check current year window; if past, check next year
      if (now >= windowStart && now <= windowEnd) return { open: true };
      const nextYear = new Date(windowStart);
      nextYear.setUTCFullYear(nextYear.getUTCFullYear() + 1);
      return { open: false, opensAt: nextYear.toISOString() };
    }

    default:
      return { open: true };
  }
}
