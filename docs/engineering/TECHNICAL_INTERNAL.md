# Legacy — Technical Internal

**Audience:** Engineers (and future-you) implementing or reviewing iOS and API behavior.  
**Last updated:** 2026-06-16  
**Companion docs:** `engineering-plan.md` (product-wide), `api-contract.md` (wire format), `collab-log.md` (decisions)

---

## 1. Architecture

### 1.1 System data flow

```
┌─────────────────────────────────────────────────────────────────┐
│  iOS (SwiftUI, iOS 17+)                                         │
│  LegacyApp → feature coordinators → APIClient / LocationEngine  │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTPS JSON  /v1/*
                             │ Headers: Authorization, X-Request-Timestamp,
                             │          X-App-Version, X-Device-Id
┌────────────────────────────▼────────────────────────────────────┐
│  REST API (TypeScript/Node, Vercel Functions)                   │
│  - Validate (lat,lng,accuracy_m) → discard immediately          │
│  - Return teasers (no coords) or signed media URLs post-unlock  │
└────────────┬───────────────────────────────┬────────────────────┘
             │                               │
┌────────────▼────────────┐    ┌─────────────▼─────────────┐
│  PostgreSQL + geohash   │    │  S3 (private, signed URLs) │
└─────────────────────────┘    └───────────────────────────┘
```

**Central invariant:** coordinates submitted on `/discovery/scan` and `/memories/{id}/unlock` are validated against immutable drop points and **never persisted** in request logs or audit tables.

### 1.2 iOS module dependency graph

Eight Swift Package Manager library targets under `ios/LegacyModules/`:

```
DesignSystem          (no deps)
APIClient             (no deps — includes KeychainSessionStore)
LocationEngine        (no deps)
LegacyAPIStubs        → APIClient          [debug/test/preview ONLY — not linked by app]
DropFeature           → DesignSystem, APIClient, LocationEngine
WanderFeature         → DesignSystem, APIClient, LocationEngine
MemoryLaneFeature     → DesignSystem, APIClient
ImportFeature         → DesignSystem, APIClient, LocationEngine
Legacy app target     → WanderFeature (+ transitive)
```

**Pattern:** MVVM with `@Observable` coordinators. No TCA. Feature modules do not depend on each other — only on shared infrastructure.

### 1.3 Layering inside APIClient

```
LegacyAPIClient
  ├── LegacyAPIConfiguration (baseURL, appVersion, deviceID)
  ├── HTTPTransport protocol  ← URLSession (prod) | StubHTTPTransport (tests)
  ├── makeURLRequest()        ← header injection, Keychain token read
  ├── validate(status:)       ← HTTP status → LegacyAPIError (pure mapping)
  └── APIEndpoints.swift      ← Codable models + typed methods (auth, scan, unlock…)
```

**Dependency inversion:** `LegacyAPIClient` never calls `URLSession.shared` directly. Tests and SwiftUI previews inject `StubHTTPTransport` without network or global mocks.

---

## 2. State management

### 2.1 Session auth state

| State | Storage | Lifetime |
|---|---|---|
| Session JWT | Keychain (`KeychainSessionStore`, `kSecAttrAccessibleAfterFirstUnlock`) | Until logout, expiry (~30d), or account deletion |
| Device ID | `identifierForVendor` at config time | Per install |
| Refresh token | **None in Phase 1** | N/A |

On `401` / `token_expired`, `LegacyAPIClient` throws `LegacyAPIError.unauthorized` — **no silent refresh**. UI must route to auth flow.

### 2.2 Location state (LocationEngine)

| State | Storage | Notes |
|---|---|---|
| `authorizationStatus` | In-memory on `@Observable LocationEngine` | Updated via `CLLocationManagerDelegate` |
| `latestFix` | In-memory (`LocationFix`: lat/lng/accuracy_m only) | No heading/course/speed — no position trail |
| `lastScanLocation` / `lastScanDate` | In-memory movement-gate bookkeeping | Reset by `recordScan(at:)` after a successful `/scan` |

**Never persisted to disk:** current location, scan history, others' coordinates.

### 2.3 Wander warmth state

`WanderCoordinator.warmthIntensity` (or future `WarmthLevel`) is derived from the **server's `warmth` field** on scan teasers (`coarse` | `approaching` | `in_bubble`). Client may **ease animations locally** between band transitions; it must not infer finer-grained proximity (DEC-15).

### 2.4 Planned persistence (not yet implemented)

| Data | Store | Rule |
|---|---|---|
| Interrupted drop drafts | SwiftData | Photo + pending `memory_id` + upload state only |
| Unlocked own-memory pins | Cache | Own coords only — never others' |

---

## 3. Logic flows

### 3.1 Authenticated request pipeline

```
Coordinator calls LegacyAPIClient.scan(body)
  → makeURLRequest(LegacyRequest)
      → read token from KeychainSessionStore.read()
      → set Authorization, X-Request-Timestamp (RFC3339 UTC),
        X-App-Version, X-Device-Id, Content-Type
  → HTTPTransport.data(for:)
  → validate(status:data:headers:)
      → 2xx: decode body
      → 401: LegacyAPIError.unauthorized(code:)
      → 423: LegacyAPIError.locked(code:, info: LockedInfo)
      → 429: LegacyAPIError.rateLimited(retryAfter:)
  → JSONDecoder → ScanResponse?
      → 204 / empty → nil
```

### 3.2 Foreground scan loop (Wander — planned M2)

```
LocationEngine.acquireFix() → LocationFix
  → if ScanMovementGate.shouldTriggerScan(...) OR engine.shouldScan(...)
      → POST /v1/discovery/scan { lat, lng, accuracy_m }
      → parse teasers[] (no coordinates in response)
      → map teaser.warmth → WarmthLevel → WarmthCueOverlay
      → recordScan(at:) to reset movement gate
```

Movement gate thresholds: **>25 m** or **>30 s** since last scan (constants in `ScanMovementGate`).

### 3.3 Unlock with dwell (M2)

```
User taps pin → POST /v1/memories/{id}/unlock
  → First attempt while dwell unsatisfied:
      423 { code: "dwell_required", retry_after_s: 20 }
      → UI: "Stay here a moment"
  → Scan already counted as dwell check #1 (contract §4)
  → Second attempt ≥20s later:
      200 → signed media URLs + find_recorded
```

`StubHTTPTransport.happyPath()` models this with a **response queue**: first `/unlock` → 423, second → 200.

### 3.4 Drop flow (M1 — planned)

```
Capture photo → strip EXIF (ImageIO, synchronous)
  → POST /v1/memories → { memory_id, upload.signed_put_url }
  → Background URLSession PUT to S3 (resumable)
  → Server webhook: EXIF re-strip, CSAM scan, thumbnail
```

---

## 4. Dependencies

### 4.1 iOS (system frameworks)

| Module | Frameworks | Why |
|---|---|---|
| DesignSystem | SwiftUI | Tokens, warmth overlay, button styles |
| APIClient | Foundation, Security | HTTP + Keychain |
| LocationEngine | CoreLocation | Foreground fixes, movement gate |
| DropFeature (future) | PhotosUI, AVFoundation, ImageIO | Picker, camera, EXIF strip |
| WanderFeature (future) | MapKit | Basemap, annotations |

**Minimum deployment:** iOS 17 (`@Observable`, `CLMonitor` at M4, App Attest at M5).

### 4.2 Backend (locked decision 2026-06-16)

- **Runtime:** TypeScript/Node (Hono or Fastify)
- **Database:** PostgreSQL + geohash spatial index
- **Deploy:** Vercel Functions (Fluid Compute)
- **Storage:** S3-compatible, signed PUT/GET only
- **Auth:** Apple/Google OAuth + email OTP; stateless JWT validation

### 4.3 LegacyAPIStubs (test harness)

| Component | Role |
|---|---|
| `StubHTTPTransport` | Offline `HTTPTransport`; path-suffix routing; per-route response queues |
| `LegacyFixtures` | Contract-shaped JSON; `validateAll()` decodes into APIClient models |
| `LegacyAPIClient.stubbed()` | One-liner for previews/tests |

**Not linked by the app target** — stubs never ship to production.

---

## 5. Edge cases and gotchas

### 5.1 Privacy / security

- **Warmth bands only:** A continuous `warmth_level` scalar would enable gradient-ascent trilateration even without bearing. Contract stays at 3 bands; client owns animation easing (DEC-15, locked 2026-06-16).
- **Silent accuracy rejection:** For others' memories, `accuracy_m > 50` returns the same `423 not_in_range` as genuinely being out of range. Client cannot distinguish — by design.
- **Pending scan_status:** Owner sees own `pending` media; everyone else does not (prevents duplicate uploads on perceived failure).
- **Import elevation:** `422 cannot_elevate_import` if user tries to share an imported memory without a live drop at that location.

### 5.2 LocationEngine

- **`acquireFix()` supersession:** A new fix request resumes any in-flight continuation with `LocationEngineError.superseded` to prevent leaked continuations.
- **Host compile vs device:** `#if os(iOS)` guards `authorizedWhenInUse` — package declares macOS only for `swift build` CI, not for shipping.
- **First fix always scans:** `ScanMovementGate` returns `true` when `lastScanLocation == nil`.

### 5.3 APIClient

- **Clock skew:** `X-Request-Timestamp` must be within ±5 min of server or `401 clock_skew`.
- **204 on scan:** Empty body means nothing nearby — not `200 + []`.
- **LockedInfo parsing:** `423` body may include top-level `retry_after_s`, `opens_at`, `fallback_at` in addition to the standard `error` envelope.

### 5.4 Keychain

- Service/account keys are fixed strings in `KeychainSessionStore`. Token delete on logout must call `KeychainSessionStore.delete()`.
- Simulator Keychain behaves differently from device — test auth flows on hardware before release.

---

## 6. Testing strategy

| Layer | How |
|---|---|
| APIClient unit tests | `StubHTTPTransport` + `LegacyFixtures`; status mapping without network |
| Fixture drift guard | `LegacyFixtures.validateAll()` in CI — fails if contract JSON ≠ Codable models |
| LocationEngine | Pure `ScanMovementGate` tests (distance/time/first-fix) |
| UI / previews | `LegacyAPIClient.stubbed()` + feature coordinators |
| Proximity integration | GPX fixtures + backend table-driven bubble tests (backend-owned, M5) |

**Note:** `swift test` requires full Xcode (XCTest). Command Line Tools alone can run `swift build` only.

---

## 7. Build & CI commands

```bash
# iOS modules — host compile (no UIKit-dependent targets required)
cd ios/LegacyModules && swift build

# iOS tests (Xcode required)
cd ios/LegacyModules && swift test

# Dashboard
cd dashboard && npm run build

# Backend (when scaffolded)
# cd backend && npm test
```

---

## 8. Pedagogical note — why the HTTPTransport seam exists

**Problem:** Networking code that calls `URLSession` directly is hard to test, hard to preview, and couples business logic to I/O.

**Mechanism (dependency inversion):** Define a one-method protocol (`HTTPTransport`) that returns `(Data, URLResponse)`. Production uses `URLSession`; tests use `StubHTTPTransport` with canned responses. Request building (`makeURLRequest`) and response interpretation (`validate`) stay in `LegacyAPIClient` and are testable without sockets.

**Stateful flows without a server:** The stub's **response queue** per path suffix models multi-step server behavior (e.g. dwell: 423 then 200) without sleep or timers in tests — each `await client.unlock()` dequeues the next canned response.

**Trade-off vs `URLProtocol`:** Apple's `URLProtocol` intercepts real `URLSession` traffic globally (closer to wire fidelity) but is process-global, harder to compose, and awkward with Swift concurrency. The seam trades wire-level fidelity for simplicity; escalate to `URLProtocol` only if we need to assert exact byte-level HTTP serialization.

**Mental model:** Treat the client as a pipeline — `LegacyRequest` → `URLRequest` → transport → `(Data, status)` → typed model / `LegacyAPIError`. Swap the transport stage; everything else stays deterministic.

---

## 9. Current implementation status (iOS)

| Task | Status |
|---|---|
| SPM scaffold (7 feature/infra modules) | Done |
| DesignSystem (tokens, buttons, WarmthCue) | Done |
| APIClient base + contract v1 endpoints | Done |
| KeychainSessionStore | Done |
| LocationEngine + ScanMovementGate | Done |
| LegacyAPIStubs harness | Done |
| `ios-auth-ui` (AuthFeature) | Done — stubs in DEBUG; live Apple needs backend |
| Drop / Wander / Import flows | M1–M3 |

See `tasks.json` and the [dashboard](https://dashboard-two-orpin-63.vercel.app) for live status.
