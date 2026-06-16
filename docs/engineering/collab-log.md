# Collab Log

Cross-AI communication between backend (Claude Code) and iOS (Cursor).
Both sides append here. Joseph relays updates between sessions.

---

## Open questions

- [backend → ios] Does `APIClient` need to handle token refresh automatically, or will it surface a 401 and let the caller re-authenticate?
- [backend → ios] Confirm: `X-App-Version` header on every request? Format: `semver` (e.g. `1.0.0`)?

---

## Decisions made

| Date | Decision | Owner |
|---|---|---|
| 2026-06-16 | `POST /memories` returns `signed_put_url` (15-min TTL). Client uploads directly to S3. | backend |
| 2026-06-16 | `/discovery/scan` returns `204` when no memories nearby (not `200 + []`) | backend |
| 2026-06-16 | `scan_status: pending` memories visible to owner only — prevents duplicate uploads from perceived failure | backend |
| 2026-06-16 | Dwell check failure returns `423 Locked` with body `{ "reason": "dwell_required" }` | backend |
| 2026-06-16 | Accuracy rejection (>50m for others' memories) is silent — unlock returns same response as "not in range" | backend |

---

## Backend → iOS

Things Cursor needs to know before writing `APIClient` or feature code.

- All requests: `Authorization: Bearer <session_token>` + `X-Request-Timestamp` within ±5min clock skew
- `POST /memories` input: `{ lat, lng, accuracy_m, media_type }` — no photo key in request body
- `POST /memories` output: `{ memory_id, signed_put_url, expires_at }` — upload to `signed_put_url` within 15 min
- `POST /discovery/scan` input: `{ lat, lng, accuracy_m }` — location discarded server-side immediately after validation
- `POST /memories/{id}/unlock` requires two passing scan results ≥20s apart — first scan counts as check #1
- All seal/condition evaluation happens server-side at unlock time — client never evaluates seals
- EXIF must be stripped client-side before upload (server also strips, but client strip is the privacy guarantee)

---

## iOS → Backend

Things Claude Code needs to know before finalizing API shapes or DB schema.

*(Cursor: append here)*

---

## Resolved

*(Move items here once both sides have acted on them)*
