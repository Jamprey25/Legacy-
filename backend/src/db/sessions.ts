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
