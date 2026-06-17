// Condition persistence. One condition per memory (PRIMARY KEY on memory_id).
// THE invariant: condition_time_fallback is NOT NULL — no memory can be stranded
// behind an unsatisfiable condition. The route rejects a missing fallback with
// 422 seal_config_invalid before reaching here (defence in depth with the DB constraint).

import { sql } from "./client.js";

export type ConditionType =
  | "time_of_day"
  | "season"
  | "weather"
  | "co_presence"
  | "long_absence"
  | "nth_return";

export interface CreateConditionInput {
  memoryId: string;
  conditionType: ConditionType;
  config: Record<string, unknown>;
  timeFallback: string; // ISO-8601 — mandatory
}

/** Insert a condition row. timeFallback is mandatory (mirrors DB NOT NULL). */
export async function createCondition(input: CreateConditionInput): Promise<void> {
  await sql`
    INSERT INTO conditions (memory_id, condition_type, config, condition_time_fallback)
    VALUES (
      ${input.memoryId},
      ${input.conditionType},
      ${JSON.stringify(input.config)}::jsonb,
      ${input.timeFallback}
    )
  `;
}
