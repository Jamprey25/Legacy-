// Device registration routes (api-contract.md §7):
//   POST /v1/devices/apns — store or refresh APNs token for the authenticated device.

import { Hono } from "hono";
import { ApiError } from "../lib/errors.js";
import { requireAuth, type AuthVars } from "../middleware/auth.js";
import { updateApnsToken } from "../db/sessions.js";
import { audit } from "../lib/audit.js";

export const devicesRoutes = new Hono<{ Variables: AuthVars }>();

devicesRoutes.use("*", requireAuth);

devicesRoutes.post("/apns", async (c) => {
  const body = await c.req.json<{ apns_token?: string }>();
  const token = body.apns_token?.trim();
  if (!token) {
    throw new ApiError("invalid_request", "Missing APNs token.");
  }

  const deviceId = c.req.header("X-Device-Id");
  if (!deviceId) {
    throw new ApiError("invalid_request", "Missing X-Device-Id header.");
  }

  const userId = c.get("userId");
  await updateApnsToken(userId, deviceId, token);
  audit(c, "device.apns_register", { device_id: deviceId }, userId);
  return c.body(null, 204);
});
