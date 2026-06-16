// Auth routes (api-contract.md §2):
//   POST /v1/auth/social        — Apple/Google identity token → session
//   POST /v1/auth/email/start   — begin email OTP (always 204)
//   POST /v1/auth/email/verify  — OTP + dob → session
//   POST /v1/auth/logout        — revoke device session
//
// Age gate runs at token exchange: under-13 rejected (resolveAgeTier throws), 13–15 minor.

import { Hono } from "hono";
import { ApiError } from "../lib/errors.js";
import { resolveAgeTier } from "../lib/age.js";
import { verifyAppleToken, verifyGoogleToken, signSession } from "../lib/jwt.js";
import { sendOtpEmail } from "../lib/email.js";
import {
  findOrCreateByProvider,
  findOrCreateByEmail,
  findExistingByProvider,
  findExistingByEmail,
  type User,
} from "../db/users.js";
import { issueCode, verifyCode } from "../db/otp.js";
import { upsertSession, revokeSession, type DeviceInfo } from "../db/sessions.js";
import { requireAuth, type AuthVars } from "../middleware/auth.js";

export const authRoutes = new Hono<{ Variables: AuthVars }>();

/** Build the contract-shaped session response (§2). */
async function sessionResponse(user: User, device: DeviceInfo | undefined) {
  if (device) await upsertSession(user.id, device);
  const { token, expiresAt } = await signSession(user.id, user.age_tier);
  return {
    session_token: token,
    expires_at: expiresAt.toISOString(),
    user: { id: user.id, age_tier: user.age_tier, is_new: user.is_new },
  };
}

authRoutes.post("/social", async (c) => {
  const body = await c.req.json<{
    provider?: "apple" | "google";
    identity_token?: string;
    dob?: string;
    device?: DeviceInfo;
  }>();

  if (body.provider !== "apple" && body.provider !== "google") {
    throw new ApiError("invalid_request", "Unknown sign-in provider.");
  }
  if (!body.identity_token) throw new ApiError("invalid_request", "Missing identity token.");

  const identity =
    body.provider === "apple"
      ? await verifyAppleToken(body.identity_token)
      : await verifyGoogleToken(body.identity_token);

  // First sign-in needs DOB for the age gate. Returning users: look up without DOB.
  const existing = await findExistingByProvider(body.provider, identity.sub);
  if (existing) return c.json(await sessionResponse(existing, body.device), 201);

  if (!body.dob) throw new ApiError("dob_required", "Date of birth is required to sign up.");
  const ageTier = resolveAgeTier(body.dob); // throws age_restricted for under-13
  const user = await findOrCreateByProvider(body.provider, identity.sub, identity.email, body.dob, ageTier);
  return c.json(await sessionResponse(user, body.device), 201);
});

authRoutes.post("/email/start", async (c) => {
  const body = await c.req.json<{ email?: string }>();
  // Always 204 — never reveal whether the address is known (no account enumeration).
  if (body.email && /.+@.+\..+/.test(body.email)) {
    const code = await issueCode(body.email);
    await sendOtpEmail(body.email, code);
  }
  return c.body(null, 204);
});

authRoutes.post("/email/verify", async (c) => {
  const body = await c.req.json<{ email?: string; code?: string; dob?: string; device?: DeviceInfo }>();
  if (!body.email || !body.code) throw new ApiError("invalid_request", "Email and code are required.");

  await verifyCode(body.email, body.code); // throws invalid_code

  const existing = await findExistingByEmail(body.email);
  if (existing) return c.json(await sessionResponse(existing, body.device), 201);

  if (!body.dob) throw new ApiError("dob_required", "Date of birth is required to sign up.");
  const ageTier = resolveAgeTier(body.dob);
  const user = await findOrCreateByEmail(body.email, body.dob, ageTier);
  return c.json(await sessionResponse(user, body.device), 201);
});

authRoutes.post("/logout", requireAuth, async (c) => {
  const body = await c.req.json<{ device_id?: string }>().catch(() => ({ device_id: undefined }));
  const userId = c.get("userId");
  if (userId && body.device_id) await revokeSession(userId, body.device_id);
  return c.body(null, 204);
});
