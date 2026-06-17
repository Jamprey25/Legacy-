// Proximity bubble math (api-contract.md §4, tasks.json endpoint-scan-bubble-math).
//
// Asymmetric bubbles:
//   own memories:    base 25m + min(accuracy_m, 75m)  — generous, false positives harmless
//   others' memories: base 20m + min(accuracy_m, 25m) — tighter; accuracy > 50m → reject silently
//
// Warmth bands (coarse only — no continuous scalar, DEC-15):
//   in_bubble:   distance <= unlockRadius
//   approaching: distance <= unlockRadius * 3
//   coarse:      in geohash zone but outside approaching band
//
// Debounce: warmth is rounded to bands server-side so boundary oscillation can't be
// used as a fine-grained signal.

import { distanceMetres } from "./geohash.js";

export type WarmthBand = "in_bubble" | "approaching" | "coarse";

export interface ProximityResult {
  inBubble: boolean;
  warmth: WarmthBand;
  distanceM: number;
}

/** Compute proximity for an own memory (no accuracy gating). */
export function ownMemoryProximity(
  userLat: number,
  userLng: number,
  accuracyM: number,
  memoryLat: number,
  memoryLng: number,
): ProximityResult {
  const distance = distanceMetres(userLat, userLng, memoryLat, memoryLng);
  const unlockRadius = 25 + Math.min(accuracyM, 75);
  const inBubble = distance <= unlockRadius;
  const warmth: WarmthBand =
    inBubble ? "in_bubble" : distance <= unlockRadius * 3 ? "approaching" : "coarse";
  return { inBubble, warmth, distanceM: distance };
}

/**
 * Compute proximity for another user's memory.
 * Returns null if accuracy is too low (> 50m) — caller should silently exclude.
 */
export function othersMemoryProximity(
  userLat: number,
  userLng: number,
  accuracyM: number,
  memoryLat: number,
  memoryLng: number,
): ProximityResult | null {
  if (accuracyM > 50) return null; // silent reject per DEC-15
  const distance = distanceMetres(userLat, userLng, memoryLat, memoryLng);
  const unlockRadius = 20 + Math.min(accuracyM, 25);
  const inBubble = distance <= unlockRadius;
  const warmth: WarmthBand =
    inBubble ? "in_bubble" : distance <= unlockRadius * 3 ? "approaching" : "coarse";
  return { inBubble, warmth, distanceM: distance };
}
