// User repository. Find-or-create by external identity (Apple/Google) or email.
// The age tier is set once at first sign-in (see lib/age.ts). DOB is immutable after.
//
// Column names cannot be bind parameters, so the Apple/Google branches use literal
// SQL rather than interpolating a column name — no dynamic identifier injection.

import { sql } from "./client.js";
import type { AgeTier } from "../lib/age.js";

export interface User {
  id: string;
  age_tier: AgeTier;
  is_new: boolean;
}

type Provider = "apple" | "google";
type UserRow = { id: string; age_tier: AgeTier };

/**
 * Find a user by provider sub, or create one. DOB + age tier are only applied on
 * creation. Returns is_new so the caller can surface first-run UX.
 */
export async function findOrCreateByProvider(
  provider: Provider,
  sub: string,
  email: string | null,
  dobISO: string,
  ageTier: AgeTier,
): Promise<User> {
  const existing =
    provider === "apple"
      ? await sql`SELECT id, age_tier FROM users WHERE apple_sub = ${sub} LIMIT 1`
      : await sql`SELECT id, age_tier FROM users WHERE google_sub = ${sub} LIMIT 1`;

  if (existing.length > 0) {
    const row = existing[0] as UserRow;
    return { id: row.id, age_tier: row.age_tier, is_new: false };
  }

  const inserted =
    provider === "apple"
      ? await sql`INSERT INTO users (dob, email, apple_sub, age_tier)
                  VALUES (${dobISO}, ${email}, ${sub}, ${ageTier}) RETURNING id, age_tier`
      : await sql`INSERT INTO users (dob, email, google_sub, age_tier)
                  VALUES (${dobISO}, ${email}, ${sub}, ${ageTier}) RETURNING id, age_tier`;

  const row = inserted[0] as UserRow;
  return { id: row.id, age_tier: row.age_tier, is_new: true };
}

/** Look up an existing user by provider sub WITHOUT creating. Returns null if absent. */
export async function findExistingByProvider(provider: Provider, sub: string): Promise<User | null> {
  const rows =
    provider === "apple"
      ? await sql`SELECT id, age_tier FROM users WHERE apple_sub = ${sub} LIMIT 1`
      : await sql`SELECT id, age_tier FROM users WHERE google_sub = ${sub} LIMIT 1`;
  if (rows.length === 0) return null;
  const row = rows[0] as UserRow;
  return { id: row.id, age_tier: row.age_tier, is_new: false };
}

/** Look up an existing user by email WITHOUT creating. Returns null if absent. */
export async function findExistingByEmail(email: string): Promise<User | null> {
  const rows = await sql`SELECT id, age_tier FROM users WHERE email = ${email} LIMIT 1`;
  if (rows.length === 0) return null;
  const row = rows[0] as UserRow;
  return { id: row.id, age_tier: row.age_tier, is_new: false };
}

/** Look up a user by id. Returns null if absent. */
export async function findById(userId: string): Promise<{ id: string; email: string | null; age_tier: AgeTier } | null> {
  type FullRow = { id: string; email: string | null; age_tier: AgeTier };
  const rows = await sql`SELECT id, email, age_tier FROM users WHERE id = ${userId} LIMIT 1`;
  if (rows.length === 0) return null;
  return rows[0] as unknown as FullRow;
}

/** Find-or-create by verified email (OTP path). */
export async function findOrCreateByEmail(
  email: string,
  dobISO: string,
  ageTier: AgeTier,
): Promise<User> {
  const existing = await sql`SELECT id, age_tier FROM users WHERE email = ${email} LIMIT 1`;
  if (existing.length > 0) {
    const row = existing[0] as UserRow;
    return { id: row.id, age_tier: row.age_tier, is_new: false };
  }

  const inserted = await sql`
    INSERT INTO users (dob, email, age_tier)
    VALUES (${dobISO}, ${email}, ${ageTier})
    RETURNING id, age_tier
  `;
  const row = inserted[0] as UserRow;
  return { id: row.id, age_tier: row.age_tier, is_new: true };
}

/** Collect all media_key values for a user's memories (for storage cleanup before delete). */
export async function listUserMediaKeys(userId: string): Promise<string[]> {
  const rows = await sql`
    SELECT media_key FROM memories
    WHERE owner_id = ${userId} AND media_key IS NOT NULL
  `;
  return rows.map((r) => r.media_key as string);
}

/**
 * Hard-delete the user and all their data.
 * FK CASCADE handles: memories → finds, presence_pings, seals, conditions, imports, sessions.
 * Caller must collect media keys BEFORE calling this and clean up storage separately.
 */
export async function deleteUser(userId: string): Promise<void> {
  await sql`DELETE FROM users WHERE id = ${userId}`;
}

/** Fetch all memories for export (owner only, includes own lat/lng). */
export async function listAllMemoriesForExport(userId: string): Promise<Array<{
  id: string;
  lat: number;
  lng: number;
  media_type: string;
  source: string;
  scan_status: string;
  media_key: string | null;
  caption: string | null;
  teaser_text: string | null;
  created_at: Date;
}>> {
  const rows = await sql`
    SELECT id, lat, lng, media_type, source, scan_status, media_key, caption, teaser_text, created_at
    FROM memories
    WHERE owner_id = ${userId}
    ORDER BY created_at ASC
  `;
  return rows as unknown as Array<{
    id: string; lat: number; lng: number; media_type: string;
    source: string; scan_status: string; media_key: string | null;
    caption: string | null; teaser_text: string | null; created_at: Date;
  }>;
}
