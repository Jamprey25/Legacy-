// App Attest enforcement for sensitive routes (SEC-P2-8).
//
// When APP_ATTEST_REQUIRED=true, drop/unlock/scan require a valid assertion plus the
// challenge_token the client used to generate it (api-contract attestation field).

import { ApiError } from "../lib/errors.js";
import { isAttestRequired, verifyAssertion } from "./appAttest.js";
import { advanceCounter, getAttestationByDevice } from "../db/attestations.js";
import { audit } from "./audit.js";
import type { Context } from "hono";

export interface AppAttestBodyFields {
  attestation?: unknown;
  challenge_token?: unknown;
}

/** Verify App Attest assertion when the feature flag is on; no-op otherwise. */
export async function verifyAppAttestForRequest(
  c: Context,
  body: AppAttestBodyFields,
): Promise<void> {
  if (!isAttestRequired()) return;

  const deviceId = c.req.header("X-Device-Id");
  const userId = c.get("userId") as string | undefined;
  if (!userId) {
    throw new ApiError("unauthorized", "Authentication required.");
  }
  if (!deviceId) {
    throw new ApiError("invalid_request", "Missing X-Device-Id header.");
  }

  const attestation = body.attestation;
  const challengeToken = body.challenge_token;
  if (typeof attestation !== "string" || !attestation.trim()) {
    throw new ApiError("unauthorized", "App attestation required.");
  }
  if (typeof challengeToken !== "string" || !challengeToken.trim()) {
    throw new ApiError("unauthorized", "App attestation challenge required.");
  }

  const record = await getAttestationByDevice(deviceId);
  if (!record || record.userId !== userId) {
    audit(c, "attest.assertion_fail", { device_id: deviceId, reason: "device_not_registered" });
    throw new ApiError("attestation_invalid", "Device not attested.");
  }

  try {
    const { counter } = await verifyAssertion(
      attestation,
      challengeToken,
      record.publicKeySpki,
      record.counter,
    );
    const ok = await advanceCounter(record.id, record.counter, counter);
    if (!ok) {
      audit(c, "attest.assertion_fail", { device_id: deviceId, reason: "counter_replay" });
      throw new ApiError("attestation_invalid", "App attestation verification failed.");
    }
  } catch (err) {
    if (err instanceof ApiError) throw err;
    audit(c, "attest.assertion_fail", { device_id: deviceId, reason: "verification_failed" });
    throw new ApiError("attestation_invalid", "App attestation verification failed.");
  }
}
