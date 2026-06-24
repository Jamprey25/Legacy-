# Legacy — API Contract (v1)

**Status:** Phase 1 (M0–M5). This is the authoritative request/response contract. iOS `APIClient` codes to this; backend implements to this. If either side needs to change a shape, update this file first, then log it in `collab-log.md`.

Engineering rationale lives in `engineering-plan.md §3`. This file is the precise wire format.

---

## 1. Conventions

- **Base URL:** `https://legacy-backend-jamprey25s-projects.vercel.app` (prod, live on Vercel). Custom domain `api.legacy.app` is aspirational/not yet configured. Configurable in `LegacyAPIConfiguration`.
- **Transport:** HTTPS only. JSON request/response bodies (`Content-Type: application/json`) except binary media uploads (direct to S3 signed URLs, not the API).
- **Versioning:** path-prefixed `/v1/...`. All endpoints below are under `/v1`.
- **Time:** all timestamps are RFC 3339 / ISO 8601 UTC strings (e.g. `2026-06-16T20:55:00Z`).
- **IDs:** all resource IDs are UUID v4 strings.
- **Coordinates:** `lat`/`lng` are JSON numbers (decimal degrees). `accuracy_m` is a number (meters, horizontal accuracy). Never returned to a non-owner.

### 1.1 Required headers (every authenticated request)

| Header | Value | Notes |
|---|---|---|
| `Authorization` | `Bearer <session_token>` | Opaque JWT from `/auth/*`. Stored in Keychain. |
| `X-Request-Timestamp` | RFC 3339 UTC | Must be within **±5 min** of server clock or request is rejected `401 clock_skew`. |
| `X-App-Version` | semver, e.g. `0.1.0` | **Confirmed header name.** iOS sends `CFBundleShortVersionString`. Used for audit + min-version gating. |
| `X-Device-Id` | stable per-install UUID | Used for App Attest binding + APNs token association. |

### 1.2 Auth model — no refresh tokens in Phase 1

**Decision (answers Cursor's open question):** Session tokens are **opaque bearer JWTs, ~30-day expiry, NO refresh token** in Phase 1.

- On `401 unauthorized` or `401 token_expired`, the client surfaces `LegacyAPIError.unauthorized` and routes the user back to the auth flow. No silent refresh.
- Rationale: a refresh-token rotation scheme is meaningful surface area for a solo builder and the UX cost of occasional re-auth (every ~30 days) is acceptable for Phase 1. Revisit if beta shows re-auth friction. Logged in `collab-log.md`.
- The token is validated **statelessly** (signature + expiry + claims). No server-side session lookup on the hot path. The `sessions` table exists only for APNs token storage and explicit revocation, not per-request validation.

### 1.3 Error envelope

All non-2xx responses use this shape:

```json
{
  "error": {
    "code": "dwell_required",
    "message": "Stay here a moment longer to open this.",
    "request_id": "req_8f3c..."
  }
}
```

- `code` is a stable machine-readable string (snake_case). iOS switches on `code`, never on `message`.
- `message` is human-readable, safe to show to the user (no internal detail, no coordinates).
- `request_id` echoes back for support/debugging. Present on every error.

### 1.4 Standard status codes

| Status | Meaning |
|---|---|
| `200` | OK, body present |
| `201` | Created |
| `204` | OK, intentionally empty body (e.g. scan with nothing nearby) |
| `400` | Malformed request / validation failure (`code`: `invalid_request`, `invalid_coordinates`, …) |
| `401` | Auth failure (`code`: `unauthorized`, `token_expired`, `clock_skew`) |
| `403` | Authenticated but not allowed (`code`: `forbidden`, `age_restricted`) |
| `404` | Resource not found (also used to avoid leaking existence) |
| `409` | Conflict (`code`: `cooldown_active`, `idempotency_replay` returns prior result) |
| `422` | Semantically invalid (`code`: `cannot_elevate_import`, `seal_config_invalid`) |
| `423` | Locked — proximity/dwell/seal not satisfied (`code`: `not_in_range`, `dwell_required`, `sealed`) |
| `429` | Rate limited (`Retry-After` header present) |
| `5xx` | Server error (`code`: `internal_error`) |

---

## 2. Auth endpoints

### `POST /v1/auth/social`
Exchange an Apple/Google identity token for a Legacy session.

**Request**
```json
{
  "provider": "apple",            // "apple" | "google"
  "identity_token": "<jwt>",
  "dob": "1998-04-12",            // required on FIRST sign-in only; ignored after
  "device": { "device_id": "<uuid>", "model": "iPhone16,2", "os_version": "17.5" }
}
```

**Response `201`**
```json
{
  "session_token": "<jwt>",
  "expires_at": "2026-07-16T20:55:00Z",
  "user": { "id": "<uuid>", "age_tier": "adult", "is_new": true }
}
```
- `age_tier`: `"adult"` (16+) | `"minor"` (13–15, restricted) | — under-13 never reaches here.
- **`403 age_restricted`** if computed age < 13. Body `message`: generic rejection. The client shows the age-gate rejection screen.
- `400 dob_required` if first sign-in without `dob`.

### `POST /v1/auth/email/start`
Begin email OTP.

**Request** `{ "email": "a@b.com" }` → **Response `204`** (always 204, even if email unknown — no account enumeration).

### `POST /v1/auth/email/verify`
**Request**
```json
{ "email": "a@b.com", "code": "418302", "dob": "1998-04-12", "device": { "device_id": "<uuid>" } }
```
**Response `201`** — same body as `/auth/social`. `401 invalid_code` on bad/expired code (codes expire 10 min, single-use).

### `POST /v1/auth/logout`
**Request** `{}` (token in header) → **Response `204`**. Revokes the session server-side (revocation list).

---

## 3. Memory creation

### `POST /v1/memories`
Create a memory record and get a signed upload URL. Drop point is set here and is immutable.

**Request**
```json
{
  "lat": 37.7749,
  "lng": -122.4194,
  "accuracy_m": 8.0,
  "media_type": "photo",          // "photo" | "text"
  "drop_method": "pin",           // "pin" | "treasure_chest" | "note_bottle"
  "privacy_tier": "private",      // Phase 1: "private" only; 422 otherwise
  "teaser_text": null,
  "cooldown_hours": 24,           // optional, default 24
  "seal": null,                   // see §6
  "condition": null,              // see §6
  "attestation": "<app-attest-assertion>"
}
```

**Response `201`**
```json
{
  "memory_id": "<uuid>",
  "upload": {
    "signed_put_url": "https://s3.../key?X-Amz-...",
    "expires_at": "2026-06-16T21:10:00Z",   // 15 min TTL
    "method": "PUT",
    "headers": { "Content-Type": "image/jpeg" }
  },
  "discoverable_after": "2026-06-17T20:55:00Z",
  "scan_status": "pending"
}
```
- For `media_type: "text"` (V4 Note in a Bottle), `upload` is `null`.
- **Vercel Blob (active backend):** `upload` is `null` for media too — the presigned-PUT model is only for the future S3/R2 backend. With Vercel Blob the client uses the §3.2 client-upload handshake instead.
- Client strips EXIF **before** uploading. Server re-strips on the storage webhook.
- `423 not_in_range` is NOT used here — drops are always allowed at the current location.
- `400 invalid_coordinates` if `accuracy_m <= 0` or `>= 1000`.
- `422 cannot_elevate_import` is reserved for the import path (§5).

### 3.2 Media upload — direct server-side upload (active path)

Storage: **Vercel Blob** (Phase 1); AWS S3 presigned GET at Phase 3 (Joseph 2026-06-18).

**Active path: `POST /v1/uploads/direct`** (shipped commit 61e9dd9 — use this).

```
POST /v1/uploads/direct
Authorization: Bearer <session_token>
Content-Type: <image/jpeg | image/png | image/webp | video/mp4>
X-Memory-Id: <memory_id>
X-Media-Position: <int >= 0>     // optional, default 0. A memory holds many photos;
                                 // 0 = hero (mirrored to memories.media_key + drives
                                 // discovery), 1+ = additional photos in capture order.
Body: raw EXIF-stripped bytes (max 25 MB)
```

Response `200`:
```json
{ "url": "https://public.blob.vercel-storage.com/memories/…/0.jpg" }
```

Flow:
1. `POST /v1/memories` → `{ memory_id, upload: null, scan_status: "pending" }`.
2. Strip EXIF client-side (iOS: `EXIFStripper.strip()`).
3. `POST /v1/uploads/direct` with stripped bytes, `X-Memory-Id: memory_id` (and
   `X-Media-Position` for photo 1+). Backend calls `@vercel/blob put()`, writes the photo to
   `memory_media`; position 0 also sets `media_key` + flips `scan_status → clear` + thumbnails.

**Multi-photo:** call once per photo with an increasing `X-Media-Position`. Reads
(`GET /:id`, unlock) return the ordered `media[]` array (hero = position 0). The
`/uploads/*` rate limit was raised **20 → 500 / hr per user** so a multi-photo import can
complete; very large imports should move to the background uploader (follow-up).

Dev/simulator: use `POST /v1/internal/webhook/storage` stub to flip `scan_status` instead
of the real upload (Vercel can't reach localhost).

**Privacy (Phase 1):** blobs are `public` with random suffix → unguessable bearer URL.
Not short-TTL. Phase 3 migrates to S3 presigned GET at unlock.

**Legacy path (kept for reference, not used by iOS):** `POST /v1/uploads` implements the
Vercel Blob client-token handshake (`@vercel/blob handleUpload`). iOS no longer calls
this endpoint; it remains available for future tooling or fallback.

**Env:** `BLOB_READ_WRITE_TOKEN` (auto-set when Blob store is linked to Vercel project).

---

## 4. Discovery — scan & unlock

### `POST /v1/discovery/scan`
Submit current location; get teasers for eligible nearby memories. **Location is validated then discarded — never persisted.**

**Request** `{ "lat": 37.7749, "lng": -122.4194, "accuracy_m": 8.0 }`

**Response `200`**
```json
{
  "teasers": [
    {
      "memory_id": "<uuid>",
      "thumbnail_url": "https://s3.../thumb?...",   // signed, short TTL; null for text/sealed
      "drop_date": "2024-09-01",
      "owner_display": "you",                        // "you" for own; display name for others (Phase 2)
      "is_own": true,
      "in_range": true,                              // true if within unlock bubble right now
      "warmth": "in_bubble",                         // "coarse" | "approaching" | "in_bubble"
      "scan_status": "clear",                        // own pending memories may show "pending"
      "pin_revealed": true,                          // true when pin should materialize on map (see below)
      "lat": 37.7749,                                // ONLY present when pin_revealed=true
      "lng": -122.4194                               // ONLY present when pin_revealed=true
    }
  ],
  "zones": [
    {
      "geohash_prefix": "9q8yykb",                  // precision-7 (~150m cell)
      "count": 3                                     // number of others' eligible memories in this cell
    }
  ]
}
```

**`pin_revealed` + coordinates (M6, dec-pin-reveal-radius):**
- Own memories: always `pin_revealed: true` with `lat`/`lng` (owner placed them).
- Others' memories: `pin_revealed: true` + `lat`/`lng` only when distance ≤ 100m (reveal radius). Beyond 100m: `pin_revealed: false`, no `lat`/`lng` fields (omitted entirely, not null).
- iOS must NOT persist revealed coordinates for others' memories — session-only from latest scan (DEC-15).

**`zones[]` (M6, dec-coarse-zone-precision):**
- Precision-7 geohash cells (~150m) with counts of others' eligible memories.
- Never contains coordinates, identity, or memory IDs — only the geohash prefix string + count.
- iOS renders as a soft heat-blob / glow overlay on the Wander map. Intensity scales by count.
- Phase 1 (private-only): zones will be empty until social tiers ship (Phase 2). iOS glow overlay is wired and ready.

**Response `204`** — no eligible memories nearby (no teasers AND no zones). Empty body. (Decided: 204, not `200 + []`.)

- Coordinates **never** appear in the response. `warmth` is the only proximity signal, and it is restricted to the **3 coarse bands** above — **never a continuous scalar** (no `warmth_level`, distance, bearing, or heading field). Rationale (resolved with iOS, collab-log Ideas): a responsive 0–1 distance proxy is a trilateration oracle — sampled from 2–3 spots it back-solves the pin with no proximity check, defeating DEC-15. The smooth gradient UX is achieved by the **client** easing animation *between* band transitions; the server only ever emits the 3 bands. Bands should be **debounced server-side** so boundary jitter can't be sampled as a fine signal. Do not add a finer field.
- This call counts as **dwell check #1** for any memory it returns `in_range: true` for (see unlock).
- `400 invalid_coordinates` on accuracy sanity failure.

### `POST /v1/memories/{id}/unlock`
Attempt to unlock a specific memory. Re-validates proximity, dwell, seals, conditions.

**Request** `{ "lat": 37.7749, "lng": -122.4194, "accuracy_m": 8.0, "attestation": "<assertion>" }`

**Response `200`**
```json
{
  "memory_id": "<uuid>",
  "media": [
    { "url": "https://s3.../full?...", "type": "photo", "expires_at": "2026-06-16T21:55:00Z" }
  ],
  "caption": "First apartment.",
  "drop_date": "2024-09-01",
  "owner_display": "you",
  "find_recorded": true,        // a Find row was written (advances nth_return / long_absence)
  "return_count": 3             // how many times this user has now found this memory
}
```

**Locked responses — all `423`, differentiated by `code`:**
| `code` | Meaning | Client UX |
|---|---|---|
| `not_in_range` | Outside the proximity bubble (or accuracy too low for others' memory — **silent**, same response) | "Walk closer." |
| `dwell_required` | In range but only one proximity check so far | "Stay here a moment." Body: `{ "retry_after_s": 20 }` |
| `sealed` | Seal not yet open | Body: `{ "opens_at": "2030-01-01T00:00:00Z" }` or `{ "opens_when": "age_based" }` |
| `condition_unmet` | Condition not satisfied and fallback not yet reached | Body: `{ "fallback_at": "..." }` |

- For **others'** memories, `not_in_range` is returned identically whether the user is genuinely out of range OR their `accuracy_m > 50`. The client cannot distinguish — by design.
- Own memories skip the dwell requirement.

---

## 5. Import (V3)

### `POST /v1/memories/import`
Batch-create private memories from on-device clusters. Idempotent.

**Request**
```json
{
  "idempotency_key": "<geohash5>:<capture-date-bucket>",
  "clusters": [
    { "lat": 37.77, "lng": -122.41, "captured_at": "2022-06-01T12:00:00Z", "asset_count": 14, "photo_count": 14 }
  ]
}
```
- `photo_count` (optional, default 1): how many photos the client will upload for this
  visit — the **whole visit**, not a cap. Clamped server-side to 1000 (anti-abuse, not
  curation). The backend pre-creates that many pending `memory_media` slots.

**Response `201`**
```json
{
  "import_id": "<uuid>",
  "memories": [
    { "cluster_index": 0, "memory_id": "<uuid>", "media_count": 14, "upload": { "signed_put_url": "...", "expires_at": "..." } }
  ]
}
```
- `media_count`: number of photos to upload for this memory. Upload each via
  `POST /v1/uploads/direct` with `X-Memory-Id` + `X-Media-Position` 0..media_count-1
  (Blob path: `upload` is `null`).
- All imported memories are `source: imported`, `privacy_tier: private`, forced.
- Replaying the same `idempotency_key` returns the **prior** result (`409 idempotency_replay` is NOT thrown; the original 201 body is returned) — safe to retry.
- Any later attempt to set a non-private tier on an imported memory → `422 cannot_elevate_import`.
- Rate limit raised **5 → 30 imports/hr per user** (5 was misread as "crashes after 5 imports").

---

## 6. Seal & condition config shapes

Embedded in `POST /v1/memories` (and the V2 compose flow). Evaluated **server-side at unlock only** — the client never evaluates these.

**Seal** (`seal` field, nullable):
```json
{ "type": "fixed_date",  "open_at": "2030-01-01T00:00:00Z" }
{ "type": "duration",    "locked_hours": 8760 }
{ "type": "age_based",   "recipient_dob": "2010-05-01", "open_at_age": 18 }
{ "type": "recurring",   "window_start": "06-01", "window_duration_hours": 168 }
```

**Condition** (`condition` field, nullable). **Must include `time_fallback`** or the request is `422 seal_config_invalid` (mirrors the DB NOT NULL constraint):
```json
{ "type": "time_of_day",  "after_hour": 18, "before_hour": 23, "time_fallback": "2027-01-01T00:00:00Z" }
{ "type": "season",       "month_start": 12, "month_end": 2,   "time_fallback": "..." }
{ "type": "weather",      "condition": "rainy",                "time_fallback": "..." }
{ "type": "co_presence",  "required_users": 3, "window_minutes": 10, "time_fallback": "..." }
{ "type": "long_absence", "days_since_last_find": 365,         "time_fallback": "..." }
{ "type": "nth_return",   "n": 3,                              "time_fallback": "..." }
```

---

## 7. Account

### `GET /v1/memories/{id}`
Owner-only full memory detail. `404` if not owner.

**Response `200`**
```json
{
  "memory_id": "<uuid>",
  "lat": 37.7749,
  "lng": -122.4194,
  "geohash": "9q8yyz...",
  "source": "live",
  "drop_method": "pin",
  "privacy_tier": "private",
  "scan_status": "clear",
  "media_type": "photo",
  "media_url": "https://blob.vercel-storage.com/...",
  "thumbnail_url": "https://blob.vercel-storage.com/...",
  "discoverable_after": "2026-06-19T11:00:00Z",
  "created_at": "2026-06-18T11:00:00Z"
}
```
- `media_url` and `thumbnail_url` are non-null only when `scan_status = "clear"` AND caller is owner. Otherwise `null`. For Vercel Blob these are the full public URLs (unguessable bearer capability); for S3/R2 they will be short-TTL signed GET URLs.
- Coordinates (`lat`, `lng`, `geohash`) are included — owner data only, never returned to non-owners.

### `GET /v1/memories` (list)
Paginated owner list for Memory Lane. Auth required.

**Query params:**
- `limit` (default 50, max 100)
- `cursor` (opaque, from `next_cursor`) — direction-aware; pass back the cursor returned by the same `sort`.
- `sort` (default `oldest`) — `oldest` | `newest`. Unknown values fall back to `oldest`.
- `media_type` (optional filter) — `photo` | `video` | `text`. Unknown values are ignored (no filter).

**Response `200`**
```json
{
  "memories": [
    {
      "memory_id": "<uuid>",
      "drop_date": "2024-09-01",
      "created_at": "2024-09-01T14:00:00Z",
      "media_type": "photo",
      "scan_status": "clear",
      "thumbnail_url": "https://blob.vercel-storage.com/...",
      "media_url": "https://blob.vercel-storage.com/...",
      "photo_count": 12,
      "caption": "First apartment.",
      "teaser_text": "Where it all began",
      "privacy_tier": "private",
      "drop_method": "pin"
    }
  ],
  "next_cursor": "<opaque>"
}
```
- `photo_count`: cleared photos in the memory (from `memory_media`). Drives the grid
  "multi-photo" badge; hero-only memories = 1, text = 0. (GET `/:id` returns the full
  `media[]` array.)
- `thumbnail_url` is non-null only when `scan_status = "clear"` and a thumbnail has been generated. `null` for text memories, pending media, and un-thumbnailed entries.
- **`media_url`** is the full-resolution own media (owner only), non-null when `scan_status = "clear"` and the memory has media. **Render this in the grid when `thumbnail_url` is null** — server-side thumbnailing is best-effort and may be absent for imports or when `sharp` is unavailable on the function, so this guarantees Memory Lane shows the real image without a per-item unlock round-trip. Same source as `GET /:id` `media_url` — no new privacy surface (owner's own media; for Vercel Blob it is the unguessable public URL).
- `caption` / `teaser_text` are the owner's labels (or `null`) — use them to disambiguate items in a dense grid.
- `next_cursor` is `null` when there are no more pages. Cursors are sort-specific: don't reuse a cursor from `sort=oldest` with `sort=newest`.

### `GET /v1/user/export`
Synchronously packages all own memories into a JSON archive and returns a download URL. Rate-limited 3 per day.

**Response `200`**
```json
{
  "archive_url": "https://blob.vercel-storage.com/exports/.../export-....json",
  "memory_count": 42,
  "exported_at": "2026-06-18T11:00:00Z"
}
```
- Archive contains own memory metadata + own coordinates (user's data). Raw storage keys are never included — media is referenced by `memory_id`.
- For stub backend: `archive_url` is a placeholder URL; real URL requires `STORAGE_BACKEND=vercel-blob`.
- `429 rate_limited` after 3 exports in 24 h.

### `PATCH /v1/user`
Update mutable profile fields. Currently supports `display_name` only.

**Request body**
```json
{ "display_name": "Joseph" }
```
- `display_name`: string (max 100 chars) or `null` to clear (client reverts to email-derived name).
- At least one field must be present or `400 invalid_request` is returned.

**Response `200`**
```json
{ "display_name": "Joseph" }
```
- Returns `null` for `display_name` when cleared.

---

### `DELETE /v1/user`
Hard-deletes the account and all associated data synchronously. No undo.

**Response `204`** — empty body.

- Cascades: memories → finds, presence_pings, seals, conditions, imports, sessions.
- Media blobs are deleted from storage fire-and-forget after the DB rows are gone.
- Session token is invalidated by the deletion itself (user row gone → `requireAuth` will 401).

### `POST /v1/devices/apns`
Register or refresh the APNs device token for the authenticated install.

**Headers:** `Authorization`, `X-Device-Id` (required), `X-Request-Timestamp`, `X-App-Version`.

**Request**
```json
{ "apns_token": "<hex-encoded APNs device token>" }
```

**Response `204`** — token stored on the `sessions` row for `(user_id, device_id)`.

**Errors:** `401 unauthorized`, `400 invalid_request` (missing token or device id).

Push delivery (`backend-apns-push`) is a separate M4 task — this endpoint only stores the token.

---

## 8. App Attest (M5 — live)

Feature flag: `APP_ATTEST_REQUIRED` env var (default `false`). When false, assertions on
drop/unlock are accepted/skipped and bypass is audit-logged. Flip to `true` at M5 TestFlight.

Required env vars (all needed when `APP_ATTEST_REQUIRED=true`):
- `APP_ATTEST_TEAM_ID` — Apple Developer Team ID
- `APP_ATTEST_BUNDLE_ID` — App bundle ID (`app.legacy.ios`)
- `APP_ATTEST_SECRET` — 32+ byte HMAC secret for challenge tokens
- `APP_ATTEST_ROOT_CA` — PEM of Apple App Attest Root CA G2

### `GET /v1/auth/attest/challenge`

Issue a short-lived HMAC-signed challenge token (5-minute window). Call before every
`DCAppAttestService.attestKey()` or `generateAssertion()`.

```
GET /v1/auth/attest/challenge
Authorization: Bearer <session_token>
```

Response `200`:
```json
{ "challenge_token": "<random_hex>.<hmac_hex>", "expires_at": "2026-06-22T00:05:00.000Z" }
```

**iOS:** Pass `challengeToken` to `DCAppAttestService`. Client data input:
`SHA256(hex_decode(challengeToken.split(".")[0]))` per `appAttest.ts` header.

### `POST /v1/auth/attest/register`

Register a device's App Attest credential key (call once after a successful
`DCAppAttestService.attestKey()`). Idempotent on `key_id` — returns existing record on
replay.

```json
{
  "key_id": "<base64url string from DCAppAttestService>",
  "attestation": "<base64 CBOR attestation object>",
  "challenge_token": "<token from GET /challenge>"
}
```

Response `200`:
```json
{ "ok": true, "environment": "production" }
```

Errors: `403 attestation_invalid` (bad cert chain / nonce / rpIdHash / key_id mismatch).

### Assertion on drop / unlock (M5)

When `APP_ATTEST_REQUIRED=true`, `POST /v1/memories` and `POST /v1/memories/:id/unlock`
require assertion headers (enforcement middleware added at flag flip):

```
X-App-Attest-Assertion: <base64 CBOR assertion from DCAppAttestService.generateAssertion>
X-App-Attest-Challenge: <challenge_token from GET /challenge>
```

Simulator: `DCAppAttestService.isSupported` is false → send `null` / omit headers. Backend
skips verification when `APP_ATTEST_REQUIRED=false`.

---

## 9. Open items (tracked in collab-log)

- Phase 2 endpoints (recipients, friends, replies, summons) — not in this v1 contract; added when M6 starts.
