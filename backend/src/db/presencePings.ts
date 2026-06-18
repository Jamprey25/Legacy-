// Presence pings: ephemeral proximity state for dwell-check, co-presence conditions,
// and warmth band debounce. UNLOGGED table (no WAL) purged every ~3 minutes — never
// stores coordinates.
//
// Warmth debounce policy (q-warmth-temporal-debounce, resolved 2026-06-18):
//   Upgrades (coarse→approaching→in_bubble) are emitted immediately.
//   Downgrades require the new lower band to hold for 2 consecutive scans ≥15s apart.
//   last_emitted_warmth  — the band last sent on the wire to this client.
//   pending_downgrade_warmth / pending_downgrade_at — candidate lower band + when seen.

import { sql } from "./client.js";

export type WarmthBand = "coarse" | "approaching" | "in_bubble";

const BAND_RANK: Record<WarmthBand, number> = { coarse: 0, approaching: 1, in_bubble: 2 };
const DOWNGRADE_MIN_SECONDS = 15;

export interface PresencePingRow {
  memory_id: string;
  user_id: string;
  last_seen_at: Date;
  last_emitted_warmth: WarmthBand | null;
  pending_downgrade_warmth: WarmthBand | null;
  pending_downgrade_at: Date | null;
}

/** Upsert a presence ping. Called on every in-range proximity check (scan + unlock). */
export async function upsertPresencePing(memoryId: string, userId: string): Promise<void> {
  await sql`
    INSERT INTO presence_pings (memory_id, user_id, last_seen_at)
    VALUES (${memoryId}, ${userId}, now())
    ON CONFLICT (memory_id, user_id)
    DO UPDATE SET last_seen_at = now()
  `;
}

/** Fetch the most recent ping for a (memory, user) pair. */
export async function getPresencePing(
  memoryId: string,
  userId: string,
): Promise<PresencePingRow | null> {
  const rows = await sql`
    SELECT * FROM presence_pings
    WHERE memory_id = ${memoryId} AND user_id = ${userId}
    LIMIT 1
  `;
  const row = rows[0] as PresencePingRow | undefined;
  return row ?? null;
}

/**
 * Compute the debounced warmth band to emit on the wire, then persist state.
 *
 * Rules:
 *  - Upgrade (raw > last emitted): emit immediately, clear pending.
 *  - Same band: emit, clear pending.
 *  - Downgrade (raw < last emitted):
 *      If no pending, record this as the pending candidate.
 *      If pending matches raw AND ≥15s since pending_at: emit the downgrade.
 *      Otherwise: hold the last emitted band (don't emit the lower value yet).
 */
export async function debouncedWarmth(
  memoryId: string,
  userId: string,
  rawBand: WarmthBand,
): Promise<WarmthBand> {
  const ping = await getPresencePing(memoryId, userId);

  const lastEmitted = ping?.last_emitted_warmth ?? null;
  const pendingBand = ping?.pending_downgrade_warmth ?? null;
  const pendingAt = ping?.pending_downgrade_at ?? null;

  const rawRank = BAND_RANK[rawBand];
  const lastRank = lastEmitted ? BAND_RANK[lastEmitted] : -1;

  let emit: WarmthBand;
  let newPendingBand: WarmthBand | null = null;
  let newPendingAt: Date | null = null;

  if (rawRank >= lastRank) {
    // Upgrade or same — immediate.
    emit = rawBand;
  } else {
    // Downgrade candidate.
    const now = Date.now();
    const pendingAgeSec = pendingAt ? (now - new Date(pendingAt).getTime()) / 1000 : 0;
    const pendingMatches = pendingBand === rawBand;

    if (pendingMatches && pendingAgeSec >= DOWNGRADE_MIN_SECONDS) {
      // Held for ≥15s across 2 scans — emit the downgrade.
      emit = rawBand;
    } else {
      // Hold: don't emit the lower band yet.
      emit = lastEmitted ?? rawBand;
      // Record the candidate (or keep it if it already matches).
      newPendingBand = rawBand;
      newPendingAt = pendingMatches && pendingAt ? new Date(pendingAt) : new Date();
    }
  }

  // Persist updated state.
  await sql`
    INSERT INTO presence_pings (
      memory_id, user_id, last_seen_at,
      last_emitted_warmth, pending_downgrade_warmth, pending_downgrade_at
    )
    VALUES (
      ${memoryId}, ${userId}, now(),
      ${emit}, ${newPendingBand}, ${newPendingAt?.toISOString() ?? null}
    )
    ON CONFLICT (memory_id, user_id) DO UPDATE SET
      last_seen_at             = now(),
      last_emitted_warmth      = EXCLUDED.last_emitted_warmth,
      pending_downgrade_warmth = EXCLUDED.pending_downgrade_warmth,
      pending_downgrade_at     = EXCLUDED.pending_downgrade_at
  `;

  return emit;
}

/** Count distinct active users at a memory within the given window (for co_presence). */
export async function countActivePings(memoryId: string, windowMinutes: number): Promise<number> {
  const rows = await sql`
    SELECT COUNT(DISTINCT user_id) AS count
    FROM presence_pings
    WHERE memory_id = ${memoryId}
      AND last_seen_at > now() - (${windowMinutes} || ' minutes')::interval
  `;
  const row = rows[0] as { count: string } | undefined;
  return parseInt(row?.count ?? "0", 10);
}
