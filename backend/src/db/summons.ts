import { sql } from "./client.js";
import { createHash, randomInt } from "node:crypto";

export async function setUserPhone(userId: string, phoneE164: string): Promise<void> {
  await sql`UPDATE users SET phone_e164 = ${phoneE164} WHERE id = ${userId}`;
}

export async function createPhoneVerification(
  userId: string,
  phoneE164: string,
  code: string,
  expiresAt: Date,
): Promise<void> {
  const codeHash = createHash("sha256").update(code).digest("hex");
  await sql`
    INSERT INTO phone_verifications (user_id, phone_e164, code_hash, expires_at)
    VALUES (${userId}, ${phoneE164}, ${codeHash}, ${expiresAt})
  `;
}

export async function verifyPhoneCode(userId: string, phoneE164: string, code: string): Promise<boolean> {
  const codeHash = createHash("sha256").update(code).digest("hex");
  const rows = await sql`
    SELECT id FROM phone_verifications
    WHERE user_id = ${userId}
      AND phone_e164 = ${phoneE164}
      AND code_hash = ${codeHash}
      AND expires_at > now()
      AND verified_at IS NULL
    ORDER BY created_at DESC
    LIMIT 1
  `;
  if (!rows.length) return false;
  await sql`UPDATE phone_verifications SET verified_at = now() WHERE id = ${(rows[0] as { id: string }).id}`;
  await setUserPhone(userId, phoneE164);
  return true;
}

export function generateOTP(): string {
  return String(randomInt(100_000, 999_999));
}

export async function setMemoryRecipients(memoryId: string, phones: string[]): Promise<void> {
  await sql`DELETE FROM memory_recipients WHERE memory_id = ${memoryId}`;
  for (const phone of phones) {
    await sql`
      INSERT INTO memory_recipients (memory_id, phone_e164)
      VALUES (${memoryId}, ${phone})
      ON CONFLICT DO NOTHING
    `;
  }
  // Summoning is an explicit share: lift the memory to the recipients tier so the
  // scan/unlock ACL admits the listed phones. The imported_is_private DB constraint
  // still blocks elevation of V3 imports (privacy invariant — live re-drop required).
  if (phones.length > 0) {
    await sql`
      UPDATE memories SET privacy_tier = 'recipients'
      WHERE id = ${memoryId} AND privacy_tier = 'private' AND source <> 'imported'
    `;
  }
}

/**
 * Recipient ACL check: is this user's *verified* phone on the memory's recipient list?
 * Verified = users.phone_e164, which is only ever set by verifyPhoneCode.
 */
export async function isRecipientOfMemory(memoryId: string, userId: string): Promise<boolean> {
  const rows = await sql`
    SELECT 1 FROM memory_recipients mr
    JOIN users u ON u.id = ${userId}
    WHERE mr.memory_id = ${memoryId}
      AND u.phone_e164 IS NOT NULL
      AND mr.phone_e164 = u.phone_e164
    LIMIT 1
  `;
  return rows.length > 0;
}

export async function logSummons(
  memoryId: string,
  ownerUserId: string,
  recipientPhone: string,
  status: string,
): Promise<string> {
  const rows = await sql`
    INSERT INTO summons_log (memory_id, owner_user_id, recipient_phone_e164, status)
    VALUES (${memoryId}, ${ownerUserId}, ${recipientPhone}, ${status})
    RETURNING id
  `;
  return (rows[0] as { id: string }).id;
}
