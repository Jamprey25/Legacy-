# App Store Reviewer Rationale — Background Location

**App:** Legacy  
**Permission requested:** Location Always + background location (`UIBackgroundModes`: `location`, `remote-notification`)  
**Last updated:** 2026-06-18

Paste or adapt the sections below into App Store Connect → App Privacy / Review Notes when submitting TestFlight or production.

---

## What Legacy does

Legacy is a location-based memory app. Users **drop** photos or notes at places they care about. Later, when they **return** to that area, the app helps them **rediscover** and **unlock** those memories in person — not from home.

Proximity is validated **server-side**; the app never shows map pins or directions to other people's memories.

---

## Why we need background location

Foreground-only location would miss the core use case: *"You walked past a place where you left something for yourself — and you never opened the app."*

We use **low-power** background location only:

| Mechanism | Purpose | GPS usage |
|-----------|---------|-----------|
| **Significant-change location service** | Wake after ~500m+ movement to refresh which geofences are armed | No continuous GPS between wakes |
| **CLMonitor (iOS 17+)** | ~14 circular regions for the user's **own** memories + ~5 **coarse geohash cells** (never point coordinates for others) | Region monitoring only |
| **CLVisit** | Secondary re-arm when iOS detects arrive/depart at a known place | OS-driven, not polled GPS |

We do **not**:

- Track continuous GPS in the background for analytics or ads
- Show turn-by-turn navigation or bearing to memories (privacy invariant DEC-15)
- Store or transmit other users' coordinates on device

---

## Why "Always" and not "When In Use" only

"When In Use" covers **Wander** (active exploration) and **Drop** (pin at current location).

**Always** is requested only after the user has engaged with Wander (seen teasers or own pins) via an in-app explainer sheet — never on cold launch. It enables:

1. Re-arming geofences after significant movement without requiring the app to stay open  
2. Region-entry wakes that trigger a **single** foreground-quality fix → `POST /scan` → server validates proximity  
3. Generic push notification ("Something is waiting for you") when the server confirms in-range — **no memory content or coordinates in the push payload**

If the user declines Always, the app remains fully usable in foreground Wander/Drop/Lane modes.

---

## Push notifications

- Registered only after the user grants notification permission (bundled with the Always upgrade flow).  
- Payload is generic copy only; unlock still requires in-person proximity check on `/unlock`.  
- `remote-notification` background mode allows a lightweight refresh when a push arrives; no silent tracking.

---

## Data minimization

- Scan/unlock requests send lat/lng/accuracy once; **server discards coordinates** after validation (api-contract §4).  
- `/scan` responses contain **teasers only** — no coordinates, no directional warmth.  
- Background regions for others use **geohash-prefix cells**, not pin lat/lng on device.

---

## Reviewer test path (TestFlight)

1. Sign in → allow **When In Use** location  
2. Drop a memory at current location (Drop tab)  
3. Walk away 50m+ → open Wander → confirm warmth/teaser  
4. Optional: accept Always + notifications from the background-discovery sheet  
5. Kill app, walk back near the drop → expect region wake or push (if Always granted and backend APNs configured)

Simulator: use a GPX route or Features → Location; push requires a real device + provisioning.

---

## Contact

Joseph Amprey — [add support email before submission]
