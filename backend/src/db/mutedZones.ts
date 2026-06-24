// Muted-zone repository. Zones suppress proximity push notifications when the
// scanning user's current position falls inside the circle (lat/lng + radius_m).

import { sql } from "./client.js";

export interface MutedZone {
  id: string;
  lat: number;
  lng: number;
  radius_m: number;
  label: string | null;
  created_at: string;
}

type ZoneRow = { id: string; lat: number; lng: number; radius_m: number; label: string | null; created_at: Date };

export async function listMutedZones(userId: string): Promise<MutedZone[]> {
  const rows = (await sql`
    SELECT id, lat, lng, radius_m, label, created_at
    FROM muted_zones
    WHERE user_id = ${userId}
    ORDER BY created_at ASC
  `) as unknown as ZoneRow[];
  return rows.map((r) => ({
    id: r.id,
    lat: r.lat,
    lng: r.lng,
    radius_m: r.radius_m,
    label: r.label,
    created_at: r.created_at instanceof Date ? r.created_at.toISOString() : String(r.created_at),
  }));
}

export async function createMutedZone(
  userId: string,
  lat: number,
  lng: number,
  radiusM: number,
  label: string | null,
): Promise<MutedZone> {
  const rows = (await sql`
    INSERT INTO muted_zones (user_id, lat, lng, radius_m, label)
    VALUES (${userId}, ${lat}, ${lng}, ${radiusM}, ${label})
    RETURNING id, lat, lng, radius_m, label, created_at
  `) as unknown as ZoneRow[];
  const r = rows[0] as ZoneRow;
  return {
    id: r.id,
    lat: r.lat,
    lng: r.lng,
    radius_m: r.radius_m,
    label: r.label,
    created_at: r.created_at instanceof Date ? r.created_at.toISOString() : String(r.created_at),
  };
}

export async function deleteMutedZone(userId: string, zoneId: string): Promise<boolean> {
  const rows = await sql`
    DELETE FROM muted_zones
    WHERE id = ${zoneId} AND user_id = ${userId}
    RETURNING id
  `;
  return rows.length > 0;
}

const MAX_ZONES_PER_USER = 10;

export async function countMutedZones(userId: string): Promise<number> {
  const rows = (await sql`
    SELECT COUNT(*)::text AS count FROM muted_zones WHERE user_id = ${userId}
  `) as unknown as Array<{ count: string }>;
  return parseInt(rows[0]?.count ?? "0", 10);
}

export { MAX_ZONES_PER_USER };

/**
 * Returns true if (lat, lng) falls inside ANY of the user's muted zones.
 * Uses the Haversine approximation — accurate enough for city-scale radii.
 */
export async function isLocationMuted(userId: string, lat: number, lng: number): Promise<boolean> {
  // Use PostGIS-free approach: pull all zones and check in JS.
  // With ≤10 zones per user this is negligible; avoids a PostGIS dependency.
  const zones = await listMutedZones(userId);
  return zones.some((z) => haversineM(lat, lng, z.lat, z.lng) <= z.radius_m);
}

function haversineM(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6_371_000; // Earth radius in metres
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function toRad(deg: number): number {
  return (deg * Math.PI) / 180;
}
