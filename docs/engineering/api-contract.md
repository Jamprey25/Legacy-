# Legacy — API Contract (v1)

**Status:** Phase 1 (M0–M5). This is the authoritative request/response contract. iOS `APIClient` codes to this; backend implements to this. If either side needs to change a shape, update this file first, then log it in `collab-log.md`.

Engineering rationale lives in `engineering-plan.md §3`. This file is the precise wire format.

---

## 1. Conventions

- **Base URL:** `https://api.legacy.app` (prod), `https://staging-api.legacy.app` (staging). Configurable in `LegacyAPIConfiguration`.
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

### 3.2 Media upload — Vercel Blob client-upload handshake

Storage decision (Joseph 2026-06-17): **Vercel Blob now, S3 later.** Vercel Blob does
not issue S3-style presigned PUT URLs, so media uploads use a token handshake against
`POST /v1/uploads` (requires `Authorization`). The endpoint is the server side of
`@vercel/blob`'s `handleUpload`.

Flow:
1. `POST /v1/memories` → `{ memory_id, upload: null, scan_status: "pending" }`.
2. Handshake — `POST /v1/uploads` with the Blob client-token request body. The
   `clientPayload` MUST be `JSON.stringify({ memory_id })`. The backend authorizes
   (memory must belong to the caller), then returns the Blob `clientToken`.
3. Client PUTs the EXIF-stripped bytes directly to Vercel Blob using the `clientToken`
   (`access: "public"`, random suffix → unguessable URL). Allowed content types:
   `image/jpeg`, `image/png`, `image/webp`, `video/mp4`.
4. Vercel calls our `onUploadCompleted` webhook → backend stores the public blob URL as
   `media_key` and flips `scan_status → clear`.

**iOS (Cursor) — two options to drive the handshake from Swift:**
- Easiest: bundle the JS only conceptually — there is no Swift SDK, so replicate the
  two-step wire protocol of `@vercel/blob/client`'s `upload()`: (a) POST the
  `blob.generate-client-token` body to `/v1/uploads`, (b) PUT bytes to the returned blob
  upload URL with the `clientToken` as a bearer token. Capture the exact request shape
  from the `@vercel/blob` source (`packages/blob/src/client.ts`) — it is not fully
  specified in the public docs.
- Dev/simulator: `onUploadCompleted` does NOT fire on localhost. Keep using
  `POST /v1/internal/webhook/storage` (dev stub) to flip `scan_status` during simulator
  testing, exactly as today.

**Privacy trade-off (Phase 1):** blobs are `public` with a random suffix → the URL is an
unguessable bearer capability, NOT a short-TTL signed URL. A leaked URL stays valid.
Acceptable for Phase-1 private-tier; revisit before public-tier / Phase 3.

**Env:** backend needs `STORAGE_BACKEND=vercel-blob` + `BLOB_READ_WRITE_TOKEN` (auto-set
when the Blob store is linked to the Vercel project).

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
      "scan_status": "clear"                         // own pending memories may show "pending"
    }
  ]
}
```

**Response `204`** — no eligible memories nearby. Empty body. (Decided: 204, not `200 + []`.)

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
    { "lat": 37.77, "lng": -122.41, "captured_at": "2022-06-01T12:00:00Z", "asset_count": 14 }
  ]
}
```

**Response `201`**
```json
{
  "import_id": "<uuid>",
  "memories": [
    { "cluster_index": 0, "memory_id": "<uuid>", "upload": { "signed_put_url": "...", "expires_at": "..." } }
  ]
}
```
- All imported memories are `source: imported`, `privacy_tier: private`, forced.
- Replaying the same `idempotency_key` returns the **prior** result (`409 idempotency_replay` is NOT thrown; the original 201 body is returned) — safe to retry.
- Any later attempt to set a non-private tier on an imported memory → `422 cannot_elevate_import`.

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
Owner-only full memory detail (coordinates included — owner only). `404` if not owner.

### `GET /v1/user/export`
**Response `202`** `{ "job_id": "<uuid>", "status": "preparing" }`. Poll → eventually `{ "status": "ready", "archive_url": "...", "expires_at": "..." }`. Signed archive of own memories only.

### `DELETE /v1/user`
**Response `202`** `{ "status": "deletion_queued" }`. Cascade-deletes memories, media, finds, pings, sessions.

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

## 8. Open items (tracked in collab-log)

- Phase 2 endpoints (recipients, friends, replies, summons) — not in this v1 contract; added when M6 starts.
