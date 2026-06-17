import { sql } from "./client.js";

export type SealType = "fixed_date" | "duration" | "age_based" | "recurring";

export interface CreateSealInput {
  memoryId: string;
  sealType: SealType;
  config: Record<string, unknown>;
}

export async function createSeal(input: CreateSealInput): Promise<void> {
  await sql`
    INSERT INTO seals (memory_id, seal_type, config)
    VALUES (
      ${input.memoryId},
      ${input.sealType},
      ${JSON.stringify(input.config)}::jsonb
    )
  `;
}
