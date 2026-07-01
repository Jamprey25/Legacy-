// Phase 2 preview: phone OTP + summons SMS (Twilio when configured, log-only fallback).

import { Hono, type Context, type Next } from "hono";
import { ApiError } from "../lib/errors.js";
import { requireAuth, type AuthVars } from "../middleware/auth.js";
import { rateLimit } from "../middleware/rateLimit.js";
import { getMemoryByOwner } from "../db/memories.js";
import {
  createPhoneVerification,
  generateOTP,
  logSummons,
  setMemoryRecipients,
  verifyPhoneCode,
} from "../db/summons.js";

export const summonsRoutes = new Hono<{ Variables: AuthVars }>();

summonsRoutes.use("*", requireAuth);
summonsRoutes.use("*", requireAdult);
summonsRoutes.use("*", rateLimit({ name: "summons", limit: 10, windowSec: 3600, keyBy: "user" }));

/** Phase 2 preview: minors cannot send summons until product rules expand (SEC-P5-4). */
async function requireAdult(c: Context, next: Next): Promise<void> {
  const tier = c.get("ageTier") as "adult" | "minor" | undefined;
  if (tier === "minor") {
    throw new ApiError("age_restricted", "Summons are not available for your account yet.");
  }
  await next();
}

function normalizePhone(raw: string): string {
  const digits = raw.replace(/\D/g, "");
  if (digits.length < 10) throw new ApiError("invalid_request", "Invalid phone number.");
  if (raw.startsWith("+")) return `+${digits}`;
  if (digits.length == 10) return `+1${digits}`;
  return `+${digits}`;
}

summonsRoutes.post("/phone/send", async (c) => {
  const userId: string = c.get("userId");
  const body = await c.req.json<{ phone?: string }>().catch(() => ({}) as { phone?: string });
  if (!body.phone) throw new ApiError("invalid_request", "phone is required.");
  const phone = normalizePhone(body.phone);
  const code = generateOTP();
  const expiresAt = new Date(Date.now() + 10 * 60_000);
  await createPhoneVerification(userId, phone, code, expiresAt);

  const twilioSid = process.env.TWILIO_ACCOUNT_SID;
  const twilioToken = process.env.TWILIO_AUTH_TOKEN;
  const twilioFrom = process.env.TWILIO_FROM_NUMBER;
  if (twilioSid && twilioToken && twilioFrom) {
    const auth = Buffer.from(`${twilioSid}:${twilioToken}`).toString("base64");
    const params = new URLSearchParams({ To: phone, From: twilioFrom, Body: `Legacy verification code: ${code}` });
    const resp = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${twilioSid}/Messages.json`, {
      method: "POST",
      headers: { Authorization: `Basic ${auth}`, "Content-Type": "application/x-www-form-urlencoded" },
      body: params,
    });
    if (!resp.ok) throw new ApiError("internal_error", "Could not send SMS.", 502);
  } else if (process.env.NODE_ENV !== "production") {
    console.info(`[summons] dev OTP issued for ${phone}`);
  }

  return c.json({ ok: true, expires_in_s: 600 });
});

summonsRoutes.post("/phone/verify", async (c) => {
  const userId: string = c.get("userId");
  const body = await c.req.json<{ phone?: string; code?: string }>().catch(() => ({}) as { phone?: string; code?: string });
  if (!body.phone || !body.code) throw new ApiError("invalid_request", "phone and code are required.");
  const phone = normalizePhone(body.phone);
  const ok = await verifyPhoneCode(userId, phone, body.code.trim());
  if (!ok) throw new ApiError("invalid_request", "Invalid or expired code.");
  return c.json({ ok: true, phone_e164: phone });
});

summonsRoutes.post("/memories/:id/summons", async (c) => {
  const userId: string = c.get("userId");
  const memoryId = c.req.param("id");
  const body = await c.req.json<{ recipients?: string[]; place_label?: string }>().catch(() => ({}) as { recipients?: string[]; place_label?: string });
  const recipients = (body.recipients ?? []).map(normalizePhone);
  if (recipients.length === 0) throw new ApiError("invalid_request", "At least one recipient phone is required.");

  const memory = await getMemoryByOwner(memoryId, userId);
  if (!memory) throw new ApiError("not_found", "Memory not found.");

  await setMemoryRecipients(memoryId, recipients);
  const placeLabel = body.place_label?.trim() || "a place that matters";
  const link = `https://legacy.app/m/${memoryId}`;
  const message = `Someone left something for you at ${placeLabel}. Return there to unlock it: ${link}`;

  const twilioSid = process.env.TWILIO_ACCOUNT_SID;
  const twilioToken = process.env.TWILIO_AUTH_TOKEN;
  const twilioFrom = process.env.TWILIO_FROM_NUMBER;

  const results: Array<{ phone: string; status: string }> = [];
  for (const phone of recipients) {
    let status = "logged";
    if (twilioSid && twilioToken && twilioFrom) {
      const auth = Buffer.from(`${twilioSid}:${twilioToken}`).toString("base64");
      const params = new URLSearchParams({ To: phone, From: twilioFrom, Body: message });
      const resp = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${twilioSid}/Messages.json`, {
        method: "POST",
        headers: { Authorization: `Basic ${auth}`, "Content-Type": "application/x-www-form-urlencoded" },
        body: params,
      });
      status = resp.ok ? "sent" : "failed";
    } else {
      console.info(`[summons] preview SMS to ${phone}: ${message}`);
      status = "preview_logged";
    }
    await logSummons(memoryId, userId, phone, status);
    results.push({ phone, status });
  }

  return c.json({ memory_id: memoryId, summons: results });
});
