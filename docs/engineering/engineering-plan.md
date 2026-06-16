# Legacy — High-Level Engineering Plan

**Status:** Active v1 — Core product definition locked on landing page and feature set. This plan covers the implementation strategy for iOS-first, MVP-first phases.

**Ground rules for this document:**
1. The website (`legacy-preview-rho.vercel.app`) is the source of truth for product behavior and positioning. This plan covers *how* it gets built.
2. The central engineering invariant: **a memory's exact coordinates and media never reach a client before a server-side proximity check passes.** This is not optional; every architectural choice is evaluated against how cleanly it enforces this.
3. Scoped to the solo builder reality: iOS-first, Cursor/Claude Code for implementation. Architecture favors fewer moving parts over theoretical purity, with explicit extraction paths where a component might outgrow its home.

---

## 1. System overview

Four components, deliberately few:

```
┌─────────────────────────┐
│  iOS app (Swift/SwiftUI)│
│  - Memory Lane          │
│  - Wander mode          │
│  - Five drop flows      │
│  - On-device import     │
│  - Core Location engine │
└───────────┬─────────────┘
            │ HTTPS (REST + JSON)
┌───────────▼─────────────┐
│  REST API               │
│  (location validation +  │ ← all proximity math & access control
│   teaser generation)    │
└───────────┬─────────────┘
            │
┌───────────▼─────────────┐     ┌──────────────────────┐
│  PostgreSQL             │     │  APNs (push)         │
│  - Geohash spatial idx  │     │  - summons            │
│  - find records         │     │  - background nudges  │
│  - friends graph        │     └──────────────────────┘
│  - seal + condition evals
├─────────────────────────┤     ┌──────────────────────┐
│  S3-compatible storage  │     │  Third-party services│
│  - signed URLs only     │     │  - CSAM scanning     │
│  - media lifecycle      │     │  - SMS/Twilio (P2)   │
└─────────────────────────┘     │  - Content classifier│
                                 └──────────────────────┘
```

The REST API is stateless and location-agnostic: it validates coordinates and immediately discards them. No movement log, no location trail. The only persisted spatial data is each memory's immutable drop point.

---

## 2. Stack summary

| Layer | Choice | One-line why |
|---|---|---|
| Mobile | Swift + SwiftUI, min iOS 17 | iOS-first is locked; iOS 17 gives `@Observable`, `CLMonitor`, modern MapKit; no MapBox dependency required at launch |
| Backend | **REST API** (stateless, JSON) | Minimal surface for solo builder; proximity validation is pure business logic, not framework-dependent |
| Database | **PostgreSQL with geohash** | Geospatial indexing; immutable drop coordinates; O(1) nearby-memory queries |
| Storage | **S3-compatible (storage key never client-exposed)** | Signed PUT/GET URLs issued by API only; buckets private |
| Proximity logic | **API endpoint returning teaser + media URLs** | Coordinates submitted → validated at request time → discarded. Two independent checks: scan (teaser) + unlock (media) |
| Map SDK | **Apple MapKit (iOS 17+)** | Integrated; no external dependency; adequate for v1; custom style via overlays if needed |
| Auth | **Apple/Google OAuth + email OTP** | Verified server-side; age gate enforced at token exchange |
| Push | **APNs direct (token-based)** | iOS-only; no FCM/OneSignal middleware in Phase 1 |
| CSAM scanning | **Mandatory, day-one** | Hash-matching on upload; vendor selection open (PhotoDNA/Thorn/Hive); apply M0 |
| IAP | **StoreKit 2** | Premium seals (age-based, atmospheric, co-presence, recurring); vault features |

**Why stateless REST over Firebase/Supabase RPC:**
The product's core constraint (proximity-gated release) is a validation problem, not a query problem. A dedicated proximity endpoint that reads coordinates, validates, and discards them is cleaner than embedding this into declarative rules. Firebase Realtime/Firestore rules cannot express "release media only after validating distance," and Supabase RLS has the same limitation — both would require client-side validation or a proxy, which replicates work the endpoint already does.

---

## 3. API Architecture

### 3.1 Core endpoints (Phase 1)

| Endpoint | Method | Input | Output | Side effect |
|---|---|---|---|---|
| `/auth/social` | POST | provider token + device info | session token | age gate enforced; user created |
| `/memories` | POST | lat, lng, accuracy_m, media_type | memory_id, signed_put_url | memory created; cooldown window set; client uploads to signed URL |
| `/memories/import` | POST | cluster list (centroid, capture_date) | import_id, [memory_ids] | private memories created in batch |
| `/discovery/scan` | POST | lat, lng, accuracy_m | teaser[] (no coords, no media) | location submitted → validated → discarded |
| `/memories/{id}/unlock` | POST | lat, lng, accuracy_m | signed media URLs | proximity re-validated; Find recorded |
| `/memories/{id}` | GET | none | full memory (owner only) | retrieve own memory detail |
| `/user/export` | GET | none | signed archive URL | cascade delete available |

All requests carry `Authorization: Bearer <session_token>` and timestamp within clock-skew tolerance of server.

### 3.2 Privacy invariants in the API

1. **Location is stateless.** `/scan` and `/unlock` take `(lat, lng, accuracy_m)`, validate against the memory's immutable coordinates, and immediately discard the input. Nothing is logged, nothing is persisted. A CI test grep-checks that no endpoint body contains a coordinate insertion.
2. **Coordinates are never sent to clients except the owner.** A client only receives:
   - Own memories: full coordinates (after drop)
   - Others' memories (post-unlock): only teaser metadata + signed media URLs, no coordinates
3. **Accuracy is asymmetric.** Own memories: bubble expanded by min(reported_accuracy, 75m). Others' memories: base 20m, max 25m, AND rejected outright if accuracy > 50m. Rejections are silent (unlock returns "not in range").
4. **Media URLs are signed and short-lived.** Issued by API only post-unlock; S3 bucket is private; raw storage keys never leave the API.

### 3.3 Seals & Conditions (evaluated server-side at unlock time)

| Seal type | Config | When it opens |
|---|---|---|
| `none` | — | always |
| `fixed_date` | `{ open_at: timestamp }` | after open_at |
| `duration` | `{ locked_hours: int }` | after (created_at + locked_hours) |
| `age_based` | `{ dob, open_at_age: int }` | when recipient turns open_at_age |
| `recurring` | `{ window_start, window_duration_hours, next_open }` | yearly, on configured window |

| Condition type | Trigger | Fallback |
|---|---|---|
| `time_of_day` | `{ after_hour: int, before_hour: int }` | condition_time_fallback |
| `season` | `{ month_start, month_end }` | condition_time_fallback |
| `weather` | `{ condition: "rainy\|sunny\|snow" }` (cached 15 min) | condition_time_fallback |
| `co_presence` | `{ required_users: int, window_minutes: int }` | condition_time_fallback |
| `long_absence` | `{ days_since_last_find }` | condition_time_fallback |
| `nth_return` | `{ n: int }` | condition_time_fallback |

**Enforced structurally:** DB constraint refuses `condition_type NOT NULL AND condition_time_fallback IS NULL`. No user can be stranded.

---

## 4. iOS client architecture

- **Structure:** SwiftUI app with feature modules as local Swift packages (`MemoryLaneFeature`, `WanderFeature`, `DropFeature`, `ImportFeature`, `LocationEngine`, `APIClient`, `DesignSystem`). MVVM with `@Observable`; no TCA.
- **APIClient:** thin typed wrapper over REST endpoints. All requests carry session token (in Keychain, SEC compliance).
- **Local persistence:** minimal.
  - Drafts (interrupted drops) in a small SwiftData store
  - Found pins cached for offline rendering
  - **Never:** any cache of non-owned coordinates or completed unlocks
- **Upload:** background `URLSession` against signed PUT URLs (scope: one media asset only), resumable. Memory record created first (POST `/memories`), media uploaded after.
- **Location engine:** wrapper over `CLLocationManager` + `CLMonitor`. Foreground: movement-gated `scan` calls (moved >25m or >30s). Background: on significant-change wake, re-arm geofences for ~14 nearest own memories + ~5 coarse zones with eligible others' content.

---

## 5. The Five Drop Methods

Each is a separate code path with distinct privacy/composition tradeoffs:

| V# | Name | Flow | Source | Seals | Privacy | Use case |
|---|---|---|---|---|---|---|
| V1 | **Pin** | 1-tap: photo + location | Camera/selection | None (basic only) | Default private | "I'm here, I don't want to forget this" — frictionless, now |
| V2 | **Treasure Chest** | Compose: photo + teaser + seals + recipients | Camera/selection | Full suite | private/recipients/friends | "I'm hiding this intentionally for specific people with conditions" |
| V3 | **Import** | Bulk from camera roll on-device clustering | EXIF (stripped on-device) | None; private-only | Private, elevation forbidden | "Seed my map on first launch" |
| V4 | **Note in a Bottle** | Text-only; location from current GPS; compose time gate | Keyboard input | Time-only seals | private/recipients/friends | "A message for someone, locked to a time and place" |
| V5 | **Prompt** | Question at a location; responses are place-locked replies | Keyboard input | Conditions only | friends/public (P3) | "Ask people who return here what they think" — Phase 3 |

Constraint: V3 (Import) memories are **private-only**. To share imported photo at a location, owner must perform a live verified drop (V1 or V2) at that coordinates.

---

## 6. Memory Lane + Wander modes

**Memory Lane:** Grid of own memories sorted by time-since-drop (oldest first). Unlocked; read-only. Shows teaser (photo, date, "time since dropped" delta). Tap → see full memory + option to re-lock and return.

**Wander:** Full-screen map in Wander mode (basemap only, no pins visible). User walks; foreground `scan` calls at movement-gated intervals; eligible memories surface as pins with warmth cue (no coordinate leak):
- Coarse zone entry: gradient bloom + haptic
- Approaching bubble: gradient intensifies
- Post-unlock: pin shows location + media

Warmth cue is **non-directional** by design (no arrow, no compass). A directional cue enables triangulation — user walks in legs, watches gradient rise/fall, back-solves the location without proximity check. This is enforced by what the client *doesn't render*, not what the server withholds.

---

## 7. Background proximity (Phase 1: own memories only)

Three iOS mechanisms, layered:

1. **Significant-change location service** — wakes the app on cell-tower-scale movement (~500m+). On wake: fetch nearby own pins + eligible coarse zones, re-arm geofences, terminate. Near-zero battery.
2. **Region monitoring (`CLMonitor`)** — iOS caps ~20 regions per app. Budget: ~14 for user's own nearest pins (their coordinates are theirs; on-device geofencing permitted), ~5 for coarse-zone cells with eligible others (device knows only "cell 9q8yy has something," never a point), 1 spare. Regions rotated on every significant-change wake.
3. **`CLVisit` monitoring** — fires on arrive/depart at places OS thinks are meaningful; secondary re-arm trigger.

On region entry: one foreground-quality fix → one `/discovery/scan` call → server validates → push/notification only if in range.

Battery posture: steady state is *zero* location hardware use; power spent only in minutes around movement into a dense area.

---

## 8. Import pipeline (on-device, Phase 1)

1. `PHAsset` fetch filtered to photos with GPS. No image bytes leave device during clustering.
2. **On-device clustering:** grid-snap to ~150m cells, merge adjacent, rank by photo count × recency spread → present ~50 clusters.
3. User selects → one cluster = one `POST /memories/import` with the derived centroid + `captured_at` from earliest asset.
4. Each image: export via `PHImageManager`, strip EXIF client-side (rewrite via ImageIO), upload to signed PUT URL. Raw GPS never serializes off-device.
5. Server marks `source: 'imported'`, enforces private-only. Elevation to friends/public forbidden (422 `CANNOT_ELEVATE_IMPORT`) until owner performs a live drop at that location.

Idempotency key (geohash + capture-date bucket) makes import resumable without duplicates.

---

## 9. Media pipeline & the CSAM gate (mandatory, Phase 1)

Upload path: `POST /memories` → API returns signed PUT URL → client strips EXIF → background PUT → storage webhook fires.

- **Client-side EXIF strip:** client removes all metadata via ImageIO rewrite (privacy mechanism).
- **Server-side verification:** storage webhook also re-strips metadata server-side (belt-and-braces; SEC-MED-4).
- **Scan gate:** `scan_status: 'pending'` on creation. Pending assets invisible to everyone *except the owner* (owner can see their own pending media; prevents duplicate uploads from perceived failure). Hash-match → `blocked`, memory `hidden`, report filed per 18 U.S.C. §2258A.
- **Vendor selection:** decision open; PhotoDNA/Thorn/Hive. Action item regardless: **apply in M0** — approval lead time is the long pole.
- **Thumbnails:** generated server-side post-clear.

---

## 10. Friends & Recipients (Phase 2)

**Recipients tier:** phone-number-based ACL. Owner specifies E.164 numbers at drop time. Recipient must:
1. Sign up with same phone number
2. Pass proximity to the memory

Summons flow (Phase 2a): Owner can send an Apple/Twilio SMS to recipient "I left something for you here: [link]" with a deep link + generic preview text (never content). Recipient follows link → sign-in → brought to map with memory surfaced → walks to location → unlock works normally.

**Friends graph (Phase 2):** Mutual connections. Accept → friend-tier memories become discoverable if recipient is in range.

**Vault:** Phase 2 feature (paid, ~$99/yr family tier). Shared map across family members. Premium responses model: gift "keep" (user can re-earn by returning) or "vault" (memory stays unlocked once found, no re-earn).

---

## 11. Replies (Phase 2+)

A reply is a full Memory record attached to another memory's pin. Submitted by the *discoverer* of the original memory at the same location. Original owner discovers the reply only on their next return to that pin.

Replies are place-locked by design: you cannot reply to a memory from your couch. The conversation happens *at the place* across returns.

---

## 12. Anti-spoofing & integrity

- **App Attest + DeviceCheck:** validated at auth, drop, and unlock. Feature-flagged gate (allow bypass during Apple downtime; audit-logged).
- **Simulated-location rejection:** `sourceInformation.isSimulatedBySoftware` flag checked (available on iOS 17+ minimum); drop rejected if true.
- **Accuracy sanity checks:** reported accuracy must be >0, <1000m; timestamps within clock skew.
- **Server-side dwell for non-owned unlocks:** requires two passing proximity checks ≥20s apart (the scan counts as first). Compensates for no velocity/teleport detection (which would require a movement trail, violating SEC-LOC-1).
- **Deliberately rejected:** velocity/teleport detection. Requires retaining a position trail → violates privacy invariant. Accepted residual risk for Phase 1 (private-only); **must revisit before Phase 3** (public content).

---

## 13. Sealing & conditions evaluation

Evaluation happens at unlock time, server-side, never on client:

```
eligible = (
  privacy_check: owner OR recipient_match OR friend_match OR (public AND age>=16)
) AND (
  seal_open: seal_type matches current time/condition
) AND (
  condition_met: condition evaluates true OR now >= condition_time_fallback
)
```

Weather is lazy-evaluated (checked only when someone is at the pin) and cached 15min per geohash. Sunset/sunrise computed locally (solar formula). Co-presence evaluated from `presence_pings` (see below).

---

## 14. Co-presence state machine (Phase 2+)

States per (memory, gathering-window): `idle → gathering → satisfied → unlocked → reset`.

1. Each eligible person's `scan` writes `presence_ping (memory_id, user_id, last_seen_at)` — upsert with ~3min TTL.
2. Evaluator: `satisfied` when distinct fresh pings ≥ N. Satisfaction opens a ~10min unlock window for all participants.
3. Optional UX (Phase 2+ decision): "2 of 3 here" progress shown to participants only — delight, slight presence leak.
4. Pings auto-purge after TTL; table empty at steady state.

`presence_pings` as UNLOGGED table (DEC-17): avoids tuple churn/vacuum pressure without WebSocket complexity.

---

## 15. Build roadmap (Phase 1 → Phase 3)

**Phase 1 — Single-user complete**
- M0: Repo + SPM modules; Auth endpoint + DOB gate; CI. *Demo: sign in, empty Wander map.*
- M1: Quick drop + composed drop; upload + CSAM plumbing (vendor stubbed if approval pending). *Demo: drop a memory.*
- M2: `scan`/`unlock` with asymmetric bubbles, dwell, cooldown. *Demo: the core loop — drop, return, unlock.*
- M3: On-device import clustering + batch import. *Demo: fresh install → map dense in <2 min.*
- M4: Significant-change + region rotation + CLVisit; notifications; warmth cue. *Demo: phone in pocket, walk past pin, notification.*
- M5: App Attest, rate limits, audit log, account deletion/export, CSAM vendor live, App Store labels. *Exit: TestFlight beta.*

**Phase 2 — Social (Recipients → Friends → Vault)**
- M6: Phone verification, recipient ACL, share cards (iMessage/WhatsApp deep links), summons (APNs + SMS).
- M7: Friends graph, friends-tier discovery, responses/replies, seals + conditions.
- M8: Vault (family tier, premium features), recurring seals, legacy chains.

**Phase 3 — Public (network effects)**
- M9: Public memories (16+), content screening, moderation pipeline.
- M10: Institutional layer (campus, festival, tourism board).
- M11: Android.

---

## 16. Testing & tooling

- **Location simulation:** GPX fixtures for every proximity scenario (approach, drive-by, urban canyon, dwell, re-entry) in simulator and UI tests.
- **API proximity unit suite:** local PostgreSQL in CI; table-driven tests for asymmetric bubbles, seal evaluation, condition logic.
- **Privacy CI gate:** automated check that no migration adds coordinates to event logs, and no endpoint persists location inputs.
- **Staging API:** mirrors prod via same migration chain; seed scripts create dense test geography.

---

## 17. Security architecture — requirement → mechanism map

| Category | Requirement | Mechanism |
|---|---|---|
| **Auth** | Phone/OIDC + age gate | Apple/Google OAuth + email OTP; under-13 rejected at token exchange |
| **Authz** | Privacy tiers + proximity gate | API endpoint validates location + returns teaser only; media URLs signed post-unlock |
| **Location** | No movement log | Coordinates submitted → validated → discarded; CI test forbids persistence |
| **Location** | Coordinates absent from clients | Views exclude exact coords; only owner gets drop point; others get teaser + media URLs |
| **Location** | Background detection w/o tracking | Coarse geohash zones; device never holds others' exact points |
| **Location** | Anti-spoofing | App Attest + simulated-location flag + accuracy sanity + server-side dwell |
| **Media** | Private buckets + signed URLs | S3 private; PUT/GET URLs issued by API only post-unlock |
| **Media** | EXIF stripping | Client-side (privacy) + server-side (guarantee) |
| **Media** | CSAM gate | Hash-matching on upload; nothing servable pre-clear; mandatory reporting |
| **Seals** | Mandatory fallback | DB constraint forbids orphaned conditions; no stranding |
| **Logging** | Event log, never coordinates | Structured log table (event, actor, request_id); no GPS |
| **Deletion** | Cascade delete | Account deletion RPC; export job = signed archive of own memories |

---

## 18. Top risks & mitigations

1. **CSAM vendor lead time** — blocks launch. Mitigation: apply M0, build behind a stub.
2. **App Store background-location review** — mitigation: §7 architecture justifies the permission; write reviewer rationale early.
3. **GPS reality vs. the proximity promise in urban canyons** — mitigation: dwell + warmth-cue degrade gracefully; tune on real walking tests in M2, not end-of-project.
4. **Import perf on 30k-photo libraries** — mitigation: batch + resumable from day one (§8).
5. **MapKit styling limitations** — mitigation: custom overlays; adequate for v1.
6. **Velocity-check absence for public content integrity (Phase 3)** — mitigation: accepted for Phase 1 (private-only); must revisit before Phase 3 with teleport detection or other anti-spoofing.

---

## 19. Cost posture & scale

- `scan` is one geohash index + eligibility check. Scales into hundreds of thousands of users; O(memories near you).
- Media is the real cost. Free tier ~500MB/yr keeps storage bounded; thumbnails cheap. If egress bites, R2/S3+CDN behind the same URL endpoint — contained swap.
- Push fan-out is trivial at Phase 1/2 volumes.
- Cost ceiling for MVP: API hosting (~$100–200/mo small instance) + S3 (~$10–30/mo) + APNs free + CSAM vendor (varies) + analytics.
