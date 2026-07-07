// Integration tests for the Phase 2 recipient ACL (DB-backed).
// Requires a real Postgres DB. In CI: set by the postgres service container.
// Locally: point DATABASE_URL at a scratch DB and run `npm run test:integration`.
//
// Covers:
//   - findNearbyMemories: own always; others only via verified-phone recipient match
//   - countNearbyZones: never counts others' private memories (SEC fix 2026-07-06)
//   - isRecipientOfMemory: verified-phone membership check
//   - setMemoryRecipients: lifts private → recipients, but never for imports

import { describe, it, expect, beforeAll, afterAll } from "vitest";
import pg from "pg";
import { findNearbyMemories, countNearbyZones } from "../../src/db/memories.js";
import { isRecipientOfMemory, setMemoryRecipients } from "../../src/db/summons.js";
import { encode as geohashEncode, neighbours } from "../../src/lib/geohash.js";

const DB_URL = process.env.DATABASE_URL;
const skip = !DB_URL;

let pgClient: pg.Client;

// Stable test IDs — reserved UUID prefix so teardown can target them.
const OWNER = "00000000-0000-0000-0003-000000000001";
const RECIPIENT = "00000000-0000-0000-0003-000000000002"; // verified phone
const STRANGER = "00000000-0000-0000-0003-000000000003"; // no phone

const MEM_PRIVATE = "00000000-0000-0000-0004-000000000001";
const MEM_RECIPIENTS = "00000000-0000-0000-0004-000000000002";
const MEM_IMPORTED = "00000000-0000-0000-0004-000000000003";

const RECIPIENT_PHONE = "+15550001111";

// All memories dropped at the same spot; scans run from the same coordinate.
const LAT = 40.7128;
const LNG = -74.006;
const GEOHASH = geohashEncode(LAT, LNG, 9);
const COARSE = geohashEncode(LAT, LNG, 5);
const NEIGHBOURS = neighbours(COARSE);

async function cleanup(): Promise<void> {
  await pgClient.query(
    "DELETE FROM memories WHERE id::text LIKE '00000000-0000-0000-0004-%'",
  );
  await pgClient.query(
    "DELETE FROM users WHERE id::text LIKE '00000000-0000-0000-0003-%'",
  );
}

beforeAll(async () => {
  if (skip) return;
  pgClient = new pg.Client({ connectionString: DB_URL });
  await pgClient.connect();
  await cleanup();

  await pgClient.query(
    `INSERT INTO users (id, dob, email, phone_e164) VALUES
       ($1, '1990-01-01', 'acl-owner@test.legacy', NULL),
       ($2, '1990-01-01', 'acl-recipient@test.legacy', $4),
       ($3, '1990-01-01', 'acl-stranger@test.legacy', NULL)`,
    [OWNER, RECIPIENT, STRANGER, RECIPIENT_PHONE],
  );

  await pgClient.query(
    `INSERT INTO memories
       (id, owner_id, lat, lng, geohash, source, privacy_tier, scan_status, media_type, discoverable_after)
     VALUES
       ($1, $4, $5, $6, $7, 'live',     'private',    'clear', 'text', now() - interval '1 day'),
       ($2, $4, $5, $6, $7, 'live',     'recipients', 'clear', 'text', now() - interval '1 day'),
       ($3, $4, $5, $6, $7, 'imported', 'private',    'clear', 'photo', now() - interval '1 day')`,
    [MEM_PRIVATE, MEM_RECIPIENTS, MEM_IMPORTED, OWNER, LAT, LNG, GEOHASH],
  );

  await pgClient.query(
    `INSERT INTO memory_recipients (memory_id, phone_e164) VALUES ($1, $2)`,
    [MEM_RECIPIENTS, RECIPIENT_PHONE],
  );
});

afterAll(async () => {
  if (skip) return;
  await cleanup();
  await pgClient.end();
});

describe.skipIf(skip)("findNearbyMemories — recipient ACL", () => {
  it("returns all own memories to the owner regardless of tier", async () => {
    const rows = await findNearbyMemories(COARSE, NEIGHBOURS, OWNER);
    const ids = rows.map((r) => r.id);
    expect(ids).toContain(MEM_PRIVATE);
    expect(ids).toContain(MEM_RECIPIENTS);
    expect(ids).toContain(MEM_IMPORTED);
  });

  it("returns a recipients-tier memory to a listed, verified-phone user", async () => {
    const rows = await findNearbyMemories(COARSE, NEIGHBOURS, RECIPIENT);
    const ids = rows.map((r) => r.id);
    expect(ids).toContain(MEM_RECIPIENTS);
  });

  it("never returns others' private memories", async () => {
    const rows = await findNearbyMemories(COARSE, NEIGHBOURS, RECIPIENT);
    const ids = rows.map((r) => r.id);
    expect(ids).not.toContain(MEM_PRIVATE);
    expect(ids).not.toContain(MEM_IMPORTED);
  });

  it("returns nothing to a user with no verified phone", async () => {
    const rows = await findNearbyMemories(COARSE, NEIGHBOURS, STRANGER);
    expect(rows).toHaveLength(0);
  });
});

describe.skipIf(skip)("countNearbyZones — private memories never leak (SEC 2026-07-06)", () => {
  it("does not count others' private memories in zone glows", async () => {
    // STRANGER sees zero zones: the only eligible-tier memory nearby lists a
    // phone they don't have. Pre-fix, the two private memories leaked here.
    const zones = await countNearbyZones(COARSE, NEIGHBOURS, STRANGER);
    expect(zones).toHaveLength(0);
  });

  it("counts recipients-tier memories only for listed recipients", async () => {
    const zones = await countNearbyZones(COARSE, NEIGHBOURS, RECIPIENT);
    expect(zones).toHaveLength(1);
    expect(zones[0]!.count).toBe(1);
    expect(zones[0]!.geohash_prefix).toBe(GEOHASH.slice(0, 7));
  });

  it("excludes the requester's own memories from zone counts", async () => {
    const zones = await countNearbyZones(COARSE, NEIGHBOURS, OWNER);
    expect(zones).toHaveLength(0);
  });
});

describe.skipIf(skip)("isRecipientOfMemory — verified-phone membership", () => {
  it("is true for a listed, verified-phone user", async () => {
    expect(await isRecipientOfMemory(MEM_RECIPIENTS, RECIPIENT)).toBe(true);
  });

  it("is false for a user with no verified phone", async () => {
    expect(await isRecipientOfMemory(MEM_RECIPIENTS, STRANGER)).toBe(false);
  });

  it("is false for a memory with no recipient list", async () => {
    expect(await isRecipientOfMemory(MEM_PRIVATE, RECIPIENT)).toBe(false);
  });
});

describe.skipIf(skip)("setMemoryRecipients — tier elevation rules", () => {
  it("lifts a private live memory to recipients tier", async () => {
    await setMemoryRecipients(MEM_PRIVATE, [RECIPIENT_PHONE]);
    const { rows } = await pgClient.query(
      "SELECT privacy_tier FROM memories WHERE id = $1",
      [MEM_PRIVATE],
    );
    expect(rows[0].privacy_tier).toBe("recipients");
    // Restore for other tests (idempotent teardown regardless).
    await pgClient.query(
      "UPDATE memories SET privacy_tier = 'private' WHERE id = $1",
      [MEM_PRIVATE],
    );
    await pgClient.query("DELETE FROM memory_recipients WHERE memory_id = $1", [MEM_PRIVATE]);
  });

  it("never elevates an imported memory (privacy invariant)", async () => {
    await setMemoryRecipients(MEM_IMPORTED, [RECIPIENT_PHONE]);
    const { rows } = await pgClient.query(
      "SELECT privacy_tier FROM memories WHERE id = $1",
      [MEM_IMPORTED],
    );
    expect(rows[0].privacy_tier).toBe("private");
    await pgClient.query("DELETE FROM memory_recipients WHERE memory_id = $1", [MEM_IMPORTED]);
  });
});
