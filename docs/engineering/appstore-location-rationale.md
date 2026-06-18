# App Store Reviewer Rationale — Background Location Permission

**Task:** `appstore-reviewer-rationale`  
**Audience:** Apple App Review, written early (M3) per task notes to avoid submission-day scramble.  
**Background location is a common rejection point** — this doc is the source of truth for the permission justification submitted in App Store Connect and the review notes.

---

## Summary for Reviewers

Legacy is a location-based memory app. Users drop geo-anchored photos and notes at physical places; other users discover them only by physically walking to the same location. **Background location is required** so the app can detect when a user approaches a memory they or someone else has placed, and notify them — without requiring the app to be open.

The background location implementation uses the **most battery-efficient APIs available on iOS 17+**: `CLMonitor` region monitoring + significant-change location service. The device's location hardware is off between wakes. No position trail is ever stored.

---

## Why "Always" Permission Is Needed

The core feature — "find something that was left for you at this place" — only works if the app can detect proximity passively. A user walking past a memory they don't know exists cannot be expected to open the app to discover it.

Without Always authorization:
- Region entry events (`CLMonitor`) do not fire when the app is suspended.
- Significant-change wakes do not occur.
- The passive discovery loop is completely broken.
- The app degrades to a manual "open and scan" tool, which eliminates the entire value proposition.

---

## Architecture: What the App Actually Does

### Wake triggers (two complementary signals)

| Trigger | API | Power impact |
|---|---|---|
| Significant movement (~500 m+) | `startMonitoringSignificantLocationChanges()` | Near-zero — uses cell/WiFi tower changes, no GPS |
| Region boundary crossing | `CLMonitor` circular regions (iOS 17+) | Near-zero — OS-native geofence, no continuous GPS |
| Place arrive/depart | `CLVisit` | Near-zero — OS-recognized place events |

The app **never runs a continuous location loop in the background**. Location hardware is off at steady state.

### On wake: what happens

1. App receives significant-change or region-entry wake (< 10s budget).
2. Acquires a single foreground-quality GPS fix (one-shot, not streaming).
3. Calls `POST /v1/discovery/scan` with the fix — server validates proximity server-side.
4. If the server confirms a memory is within the proximity bubble, the **server** sends an APNs push notification.
5. App terminates. Hardware goes back off.

The device **never decides** whether a memory is "close enough" — that decision is made by the server from an accuracy-validated coordinate. The device only contributes a location fix; the server discards it after evaluation.

### Region management

- **~14 own-memory regions** (circular, ~25 m radius) centred on the user's own drops.
- **~5 coarse geohash zones** (~4.9 km cells) for areas where others' content may exist — the device only knows "cell 9q8yy has something", never a point coordinate.
- Total ≤ 19 regions (iOS cap is 20; one slot reserved).
- Regions are rotated on every significant-change wake: sorted by distance, nearest 19 armed.

---

## Privacy Design

| Invariant | How it's enforced |
|---|---|
| User location is never stored | `POST /scan` validates the fix and discards it immediately; no coordinate column in audit_log (CI gate enforces this) |
| Others' pin coordinates never reach the device | Scan response contains only a warmth band (`coarse/approaching/in_bubble`) and a memory_id — no lat/lng |
| No position trail | The app does not accumulate fixes; each wake is a single one-shot acquisition |
| Background location never used to infer non-proximity facts | The sole use is "is user within ~25–100 m of a known point?" |

---

## Usage String (Info.plist)

**`NSLocationAlwaysAndWhenInUseUsageDescription`** (shown to users in permission prompt):

> "Legacy uses your location in the background to notify you when you walk near a memory — a photo or note someone left for you at this place. Your location is never stored or shared."

**`NSLocationWhenInUseUsageDescription`** (fallback / When In Use prompt):

> "Legacy uses your location to show you memories near your current position. Tap a pin to open it."

---

## Permission Request Flow

The app **never calls `requestAlwaysAuthorization()` on cold launch**. The sequence:

1. On first Wander tab open: request When In Use (`requestWhenInUseAuthorization()`).
2. After the user has had at least one successful foreground scan (demonstrates value): show `BackgroundDiscoveryPermissionSheet` explaining the background use case.
3. Sheet contains a single "Allow Background Discovery" button that calls `requestAlwaysAuthorization()`.
4. If denied: app remains fully functional in foreground; background discovery is disabled gracefully.

This matches Apple's guidance to request Always only after demonstrating foreground value.

---

## App Store Connect Fields

**Background Modes** (checked in Xcode capabilities):
- `location` — Required for significant-change + region monitoring

**Privacy — Location** (Privacy Nutrition Label):
- Location: Used, Not Linked to User (proximity evaluation only; not stored or shared)

**Review Notes** (paste into the App Review Information field):

> This app uses background location exclusively to detect when the user walks near a geo-anchored memory and deliver a push notification. The implementation uses CLMonitor region monitoring and significant-change location — the two lowest-power background location APIs on iOS. The device's location hardware is off between wakes. No position data is stored server-side (confirmed by server architecture and CI enforcement). The "Always" permission prompt is shown only after the user has used the app in foreground and seen its value. We are happy to provide a demo account or GPX simulation scenario for testing.
