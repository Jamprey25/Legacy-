// Session/device records. Session JWTs are validated statelessly (no lookup here on the
// hot path); this table stores the device row for APNs token storage + explicit
// revocation. Upserted on each sign-in by (user_id, device_id).

import { sql } from "./client.js";

export interface DeviceInfo {
  device_id: string;
  model?: string | null;
  os_version?: string | null;
}

/** Record (or refresh) the device a user signed in from. */
export async function upsertSession(userId: string, device: DeviceInfo): Promise<void> {
  await sql`
    INSERT INTO sessions (user_id, device_id, model, os_version, last_seen_at)
    VALUES (${userId}, ${device.device_id}, ${device.model ?? null}, ${device.os_version ?? null}, now())
    ON CONFLICT (user_id, device_id)
    DO UPDATE SET model = EXCLUDED.model,
                  os_version = EXCLUDED.os_version,
                  last_seen_at = now(),
                  revoked_at = NULL
  `;
}

/** Revoke the device row for an explicit logout. */
export async function revokeSession(userId: string, deviceId: string): Promise<void> {
  await sql`
    UPDATE sessions SET revoked_at = now()
    WHERE user_id = ${userId} AND device_id = ${deviceId}
  `;
}

/** Return all active APNs tokens for a user (for push delivery). */
export async function getApnsTokensForUser(userId: string): Promise<string[]> {
  const rows = await sql`
    SELECT apns_token FROM sessions
    WHERE user_id = ${userId}
      AND apns_token IS NOT NULL
      AND revoked_at IS NULL
  `;
  return rows.map((r) => r.apns_token as string);
}

/** Remove a stale APNs token (Unregistered / BadDeviceToken response from APNs). */
export async function clearApnsToken(userId: string, apnsToken: string): Promise<void> {
  await sql`
    UPDATE sessions SET apns_token = NULL
    WHERE user_id = ${userId} AND apns_token = ${apnsToken}
  `;
}

/** Store or refresh the APNs token for a signed-in device row. */
export async function updateApnsToken(
  userId: string,
  deviceId: string,
  apnsToken: string
): Promise<void> {
  await sql`
    INSERT INTO sessions (user_id, device_id, apns_token, last_seen_at)
    VALUES (${userId}, ${deviceId}, ${apnsToken}, now())
    ON CONFLICT (user_id, device_id)
    DO UPDATE SET apns_token = EXCLUDED.apns_token,
                  last_seen_at = now(),
                  revoked_at = NULL
  `;
}
