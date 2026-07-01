// App Attest routes (api-contract.md §8 — M5):
//   GET  /v1/auth/attest/challenge  — issue a short-lived HMAC challenge token
//   POST /v1/auth/attest/register   — verify attestation object, store credential key

import { Hono } from "hono";
import { ApiError } from "../lib/errors.js";
import { issueAttestChallenge, verifyAttestation } from "../lib/appAttest.js";
import { insertAttestation } from "../db/attestations.js";
import { requireAuth, type AuthVars } from "../middleware/auth.js";
import { rateLimit } from "../middleware/rateLimit.js";
import { audit } from "../lib/audit.js";

export const attestRoutes = new Hono<{ Variables: AuthVars }>();

attestRoutes.use("*", requireAuth);
// Tight rate limit — registration is once per device, challenges are per-request.
// 60 per minute covers normal use; prevents challenge-fishing.
attestRoutes.use("*", rateLimit({ name: "attest", limit: 60, windowSec: 60, keyBy: "user" }));

// ---------------------------------------------------------------------------
// GET /auth/attest/challenge
// ---------------------------------------------------------------------------
// iOS calls this before every attestKey() or generateAssertion() call.
// The returned token is passed back in register/assertion requests.

attestRoutes.get("/challenge", (c) => {
  const { token, expiresAt } = issueAttestChallenge();
  return c.json({ challenge_token: token, expires_at: expiresAt.toISOString() });
});

// ---------------------------------------------------------------------------
// POST /auth/attest/register
// ---------------------------------------------------------------------------
// Called once after DCAppAttestService.attestKey() succeeds on device.
// body: { key_id: string, attestation: string (base64), challenge_token: string }

attestRoutes.post("/register", async (c) => {
  const deviceId = c.req.header("X-Device-Id");
  if (!deviceId) throw new ApiError("invalid_request", "Missing X-Device-Id header.");

  const body = await c.req.json<{
    key_id?: string;
    attestation?: string;
    challenge_token?: string;
  }>();

  if (!body.key_id || !body.attestation || !body.challenge_token) {
    throw new ApiError("invalid_request", "key_id, attestation, and challenge_token are required.");
  }

  let result;
  try {
    result = await verifyAttestation(body.attestation, body.challenge_token);
  } catch (err) {
    const msg = err instanceof Error ? err.message : "attestation verification failed";
    audit(c, "attest.register_fail", { device_id: deviceId, reason: msg });
    throw new ApiError("attestation_invalid", "Attestation verification failed.");
  }

  // Confirm that the key_id supplied by iOS matches what we derived from the cert
  if (result.derivedKeyId !== body.key_id) {
    audit(c, "attest.register_fail", { device_id: deviceId, reason: "key_id_mismatch" });
    throw new ApiError("attestation_invalid", "key_id does not match attestation certificate.");
  }

  const userId = c.get("userId");
  await insertAttestation({
    userId,
    deviceId,
    keyId: body.key_id,
    publicKeySpki: result.publicKeySpki,
    receipt: result.receipt,
    environment: result.environment,
  });

  audit(c, "attest.register", { device_id: deviceId, environment: result.environment }, userId);
  return c.json({ ok: true, environment: result.environment });
});
