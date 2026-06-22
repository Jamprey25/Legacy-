// Device attestation repository.
// Stores the App Attest credential public key registered once per device.

import { sql } from "./client.js";

export interface DeviceAttestation {
  id: string;
  userId: string;
  deviceId: string;
  keyId: string;
  publicKeySpki: Buffer;
  receipt: Buffer;
  environment: "production" | "development";
  counter: number;
}

type AttestRow = {
  id: string;
  user_id: string;
  device_id: string;
  key_id: string;
  public_key_spki: Buffer;
  receipt: Buffer;
  environment: string;
  counter: number;
};

function toAttestation(row: AttestRow): DeviceAttestation {
  return {
    id: row.id,
    userId: row.user_id,
    deviceId: row.device_id,
    keyId: row.key_id,
    publicKeySpki: row.public_key_spki,
    receipt: row.receipt,
    environment: row.environment as "production" | "development",
    counter: row.counter,
  };
}

/** Look up a device's attestation record by device_id. */
export async function getAttestationByDevice(
  deviceId: string,
): Promise<DeviceAttestation | null> {
  const rows = await sql`
    SELECT * FROM device_attestations WHERE device_id = ${deviceId} LIMIT 1
  `;
  return rows.length > 0 ? toAttestation(rows[0] as AttestRow) : null;
}

/** Insert a new attestation record (call after verifying the attestation object). */
export async function insertAttestation(opts: {
  userId: string;
  deviceId: string;
  keyId: string;
  publicKeySpki: Buffer;
  receipt: Buffer;
  environment: "production" | "development";
}): Promise<DeviceAttestation> {
  const rows = await sql`
    INSERT INTO device_attestations
      (user_id, device_id, key_id, public_key_spki, receipt, environment)
    VALUES
      (${opts.userId}, ${opts.deviceId}, ${opts.keyId},
       ${opts.publicKeySpki}, ${opts.receipt}, ${opts.environment})
    ON CONFLICT (key_id) DO NOTHING
    RETURNING *
  `;
  if (rows.length === 0) {
    // key_id already registered — return the existing record
    const existing = await sql`
      SELECT * FROM device_attestations WHERE key_id = ${opts.keyId} LIMIT 1
    `;
    return toAttestation(existing[0] as AttestRow);
  }
  return toAttestation(rows[0] as AttestRow);
}

/** Bump the counter after a valid assertion. Returns false if counter is stale (replay). */
export async function advanceCounter(
  id: string,
  expectedMinCounter: number,
  newCounter: number,
): Promise<boolean> {
  const result = await sql`
    UPDATE device_attestations
    SET counter = ${newCounter}
    WHERE id = ${id} AND counter < ${newCounter} AND counter >= ${expectedMinCounter - 1}
    RETURNING id
  `;
  return result.length > 0;
}
