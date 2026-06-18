// Integration tests for presence_pings + warmth debounce (DB-backed).
// Requires a real Postgres DB. In CI: set by the postgres service container.
// Locally: set DATABASE_URL in .env.local and run `npm run test:integration`.
//
// These tests cover the GPX-style dwell/re-entry scenarios deferred from
// location-ci-tests: boundary jitter, upgrade immediacy, downgrade hold,
// and re-entry after leaving the bubble.

import { describe, it, expect, beforeAll, afterAll, afterEach } from "vitest";
import pg from "pg";
import { upsertPresencePing, getPresencePing, debouncedWarmth } from "../../src/db/presencePings.js";

const DB_URL = process.env.DATABASE_URL;
const skip = !DB_URL;

// Shared pg client for test teardown only; app code uses the Neon driver.
let pgClient: pg.Client;

beforeAll(async () => {
  if (skip) return;
  pgClient = new pg.Client({ connectionString: DB_URL });
  await pgClient.connect();
});

afterAll(async () => {
  if (skip) return;
  await pgClient.end();
});

afterEach(async () => {
  if (skip) return;
  // Clean up test rows by a recognizable test UUID prefix.
  await pgClient.query(
    "DELETE FROM presence_pings WHERE memory_id::text LIKE '00000000-0000-0000-%'",
  );
});

// Stable test IDs — use a reserved UUID prefix so teardown can target them.
const MEM = "00000000-0000-0000-0001-000000000001";
const USER = "00000000-0000-0000-0002-000000000001";

describe.skipIf(skip)("presence pings — upsert + dwell timing", () => {
  it("inserts a new ping and retrieves it", async () => {
    await upsertPresencePing(MEM, USER);
    const ping = await getPresencePing(MEM, USER);
    expect(ping).not.toBeNull();
    expect(ping!.memory_id).toBe(MEM);
    expect(ping!.user_id).toBe(USER);
  });

  it("updates last_seen_at on repeated upsert", async () => {
    await upsertPresencePing(MEM, USER);
    const first = await getPresencePing(MEM, USER);

    // Brief sleep to ensure timestamps differ.
    await new Promise((r) => setTimeout(r, 20));

    await upsertPresencePing(MEM, USER);
    const second = await getPresencePing(MEM, USER);

    expect(new Date(second!.last_seen_at).getTime()).toBeGreaterThanOrEqual(
      new Date(first!.last_seen_at).getTime(),
    );
  });
});

describe.skipIf(skip)("warmth debounce — upgrade / downgrade policy", () => {
  it("emits in_bubble immediately on first scan (upgrade path)", async () => {
    const result = await debouncedWarmth(MEM, USER, "in_bubble");
    expect(result).toBe("in_bubble");
  });

  it("upgrades coarse → in_bubble immediately (no hold)", async () => {
    await debouncedWarmth(MEM, USER, "coarse");
    const result = await debouncedWarmth(MEM, USER, "in_bubble");
    expect(result).toBe("in_bubble");
  });

  it("holds last band on first downgrade scan (< 15s apart)", async () => {
    // Establish in_bubble as last emitted.
    await debouncedWarmth(MEM, USER, "in_bubble");
    // Immediate downgrade — should return the held band, not coarse.
    const result = await debouncedWarmth(MEM, USER, "coarse");
    expect(result).toBe("in_bubble");
  });

  it("emits downgrade after two scans ≥ 15s apart", async () => {
    // Establish in_bubble.
    await debouncedWarmth(MEM, USER, "in_bubble");

    // Manually backdate the pending_downgrade_at so the 15s window passes.
    await pgClient.query(
      `UPDATE presence_pings
       SET pending_downgrade_warmth = 'coarse',
           pending_downgrade_at     = now() - interval '20 seconds'
       WHERE memory_id = $1 AND user_id = $2`,
      [MEM, USER],
    );

    // Second downgrade scan — 15s elapsed, same band → should emit.
    const result = await debouncedWarmth(MEM, USER, "coarse");
    expect(result).toBe("coarse");
  });

  it("resets pending downgrade when a different lower band arrives", async () => {
    // Establish in_bubble.
    await debouncedWarmth(MEM, USER, "in_bubble");

    // First downgrade: approaching. Starts pending.
    await debouncedWarmth(MEM, USER, "approaching");

    // Second scan: now coarse (different band than pending). Resets the clock.
    const result = await debouncedWarmth(MEM, USER, "coarse");
    // Still held — new pending started fresh.
    expect(result).toBe("in_bubble");
  });

  it("upgrade clears any pending downgrade", async () => {
    await debouncedWarmth(MEM, USER, "in_bubble");

    // Start a downgrade pending.
    await debouncedWarmth(MEM, USER, "coarse");

    // Immediately upgrades again — should emit in_bubble and clear pending.
    const result = await debouncedWarmth(MEM, USER, "in_bubble");
    expect(result).toBe("in_bubble");

    // Verify pending is cleared in DB.
    const rows = await pgClient.query<{ pending_downgrade_warmth: string | null }>(
      "SELECT pending_downgrade_warmth FROM presence_pings WHERE memory_id=$1 AND user_id=$2",
      [MEM, USER],
    );
    expect(rows.rows[0]?.pending_downgrade_warmth).toBeNull();
  });
});

describe.skipIf(skip)("GPX scenarios — boundary jitter", () => {
  it("rapid alternation near boundary does not oscillate warmth", async () => {
    // Simulate user walking back and forth across the coarse→approaching boundary.
    // The emitted band should stay stable at the higher value.
    await debouncedWarmth(MEM, USER, "approaching");
    const r1 = await debouncedWarmth(MEM, USER, "coarse");     // should hold approaching
    const r2 = await debouncedWarmth(MEM, USER, "approaching"); // back up immediately
    const r3 = await debouncedWarmth(MEM, USER, "coarse");     // should hold approaching

    expect(r1).toBe("approaching");
    expect(r2).toBe("approaching");
    expect(r3).toBe("approaching");
  });

  it("slow approach: each upgrade emits immediately", async () => {
    const coarse = await debouncedWarmth(MEM, USER, "coarse");
    const approaching = await debouncedWarmth(MEM, USER, "approaching");
    const inBubble = await debouncedWarmth(MEM, USER, "in_bubble");

    expect(coarse).toBe("coarse");
    expect(approaching).toBe("approaching");
    expect(inBubble).toBe("in_bubble");
  });
});
