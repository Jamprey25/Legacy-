// Email OTP storage. Codes are hashed (sha-256) before storage and compared by hash.
// One active code per email (upsert). Verify is single-use and attempt-capped.

import { createHash, randomInt } from "node:crypto";
import { sql } from "./client.js";
import { ApiError } from "../lib/errors.js";

const TTL_MINUTES = 30;
const MAX_ATTEMPTS = 5;

function hashCode(code: string): string {
  return createHash("sha256").update(code).digest("hex");
}

/** Generate, store (hashed, upsert), and return a fresh 6-digit code. */
export async function issueCode(email: string): Promise<string> {
  const code = randomInt(0, 1_000_000).toString().padStart(6, "0");
  const expiresAt = new Date(Date.now() + TTL_MINUTES * 60_000);
  await sql`
    INSERT INTO email_otps (email, code_hash, expires_at, attempts)
    VALUES (${email}, ${hashCode(code)}, ${expiresAt.toISOString()}, 0)
    ON CONFLICT (email)
    DO UPDATE SET code_hash = EXCLUDED.code_hash, expires_at = EXCLUDED.expires_at, attempts = 0
  `;
  return code;
}

const failInvalidCode = () => new ApiError("invalid_code", "That code is incorrect or expired.");

async function loadOtpRow(email: string) {
  const rows = await sql`
    SELECT code_hash, expires_at, attempts FROM email_otps WHERE email = ${email} LIMIT 1
  `;
  return rows[0] as { code_hash: string; expires_at: string; attempts: number } | undefined;
}

/**
 * Validate a submitted code without consuming it. Used when signup still needs DOB so the
 * client can retry email/verify with the same OTP after the DOB screen.
 */
export async function assertValidCode(email: string, code: string): Promise<void> {
  const row = await loadOtpRow(email);
  if (!row) throw failInvalidCode();
  if (row.attempts >= MAX_ATTEMPTS || new Date(row.expires_at).getTime() < Date.now()) {
    await sql`DELETE FROM email_otps WHERE email = ${email}`;
    throw failInvalidCode();
  }
  if (row.code_hash !== hashCode(code)) {
    await sql`UPDATE email_otps SET attempts = attempts + 1 WHERE email = ${email}`;
    throw failInvalidCode();
  }
}

/**
 * Verify a submitted code. Consumes the row on success. Throws ApiError(invalid_code)
 * on mismatch/expiry/too-many-attempts — deliberately indistinguishable to the caller.
 */
export async function verifyCode(email: string, code: string): Promise<void> {
  await assertValidCode(email, code);
  await sql`DELETE FROM email_otps WHERE email = ${email}`; // single-use
}
