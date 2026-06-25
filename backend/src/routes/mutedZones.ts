// Muted-zone routes (api-contract.md §9):
//   GET    /v1/user/muted-zones        — list all zones for the authenticated user
//   POST   /v1/user/muted-zones        — create a zone (max 10 per user)
//   DELETE /v1/user/muted-zones/:id    — delete a specific zone

import { Hono } from "hono";
import { ApiError } from "../lib/errors.js";
import { requireAuth, type AuthVars } from "../middleware/auth.js";
import { validateCoordinates } from "../lib/locationInput.js";
import {
  listMutedZones,
  createMutedZone,
  deleteMutedZone,
  countMutedZones,
  MAX_ZONES_PER_USER,
} from "../db/mutedZones.js";

export const mutedZonesRoutes = new Hono<{ Variables: AuthVars }>();

mutedZonesRoutes.use("*", requireAuth);

mutedZonesRoutes.get("/", async (c) => {
  const userId: string = c.get("userId");
  const zones = await listMutedZones(userId);
  return c.json({ zones });
});

mutedZonesRoutes.post("/", async (c) => {
  const userId: string = c.get("userId");

  const body = await c.req.json<{
    lat?: unknown;
    lng?: unknown;
    radius_m?: unknown;
    label?: unknown;
  }>().catch(() => null);
  if (!body) throw new ApiError("invalid_request", "Request body must be JSON.");

  const { lat, lng } = validateCoordinates(body.lat, body.lng);

  const rawRadius = body.radius_m;
  if (rawRadius === undefined || rawRadius === null) {
    throw new ApiError("invalid_request", "radius_m is required.");
  }
  const radiusM = Number(rawRadius);
  if (!Number.isInteger(radiusM) || radiusM < 100 || radiusM > 5000) {
    throw new ApiError("invalid_request", "radius_m must be an integer between 100 and 5000.");
  }

  const rawLabel = body.label;
  let label: string | null = null;
  if (typeof rawLabel === "string") {
    const trimmed = rawLabel.trim();
    if (trimmed.length > 50) throw new ApiError("invalid_request", "label must be 50 characters or fewer.");
    label = trimmed.length > 0 ? trimmed : null;
  }

  const count = await countMutedZones(userId);
  if (count >= MAX_ZONES_PER_USER) {
    throw new ApiError("invalid_request", `You can have at most ${MAX_ZONES_PER_USER} muted zones.`);
  }

  const zone = await createMutedZone(userId, lat, lng, radiusM, label);
  return c.json({ zone }, 201);
});

mutedZonesRoutes.delete("/:id", async (c) => {
  const userId: string = c.get("userId");
  const zoneId = c.req.param("id");
  const deleted = await deleteMutedZone(userId, zoneId);
  if (!deleted) throw new ApiError("not_found", "Muted zone not found.");
  return new Response(null, { status: 204 });
});
