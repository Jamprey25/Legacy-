# Legacy — Architecture Decision Log

Running log of engineering decisions. Statuses: **Decided** (your call, veto-able), **Leaning**, **Open**, **Tension** (conflict documented), **Tabled**.

Product decisions stay in the product decision log; this file is engineering only.

---

## Foundational decisions

**DEC-1 — REST API over RPC/Supabase/Firebase** · *Decided*

Stateless REST endpoint that takes coordinates, validates them against memory drop points, and immediately discards them. Why: the core constraint (proximity gate) is a validation + authorization problem, not a query problem. No RLS or Postgres `SECURITY DEFINER` function can express "release media only after server-side distance check" without the client guessing or the server proxying. A dedicated endpoint eliminates the guess. Revisions: If a second platform (Android) or complex auth model arrives, the extraction path is clear — the API is plain JSON, auth-agnostic. Revisit if: response times exceed 200ms or DEC-2 is invalidated.

**DEC-2 — PostgreSQL + geohash for spatial index** · *Decided*

Immutable drop coordinates stored as (`latitude`, `longitude`, `geohash`). Queries via geohash prefix + radius. Why: simpler than PostGIS for this use case (no complex geometry), native in PostgreSQL, indexable, and the geohash cell concept maps to background coarse zones. Revisit if: H3 or PostGIS features become required (unlikely pre-Phase 3); geohash distortion at high latitudes surfaces real UX problems.

**DEC-3 — S3-compatible storage, never raw keys to clients** · *Decided*

API issues signed PUT URLs at drop time, signed GET URLs only post-unlock. Storage bucket is private. Why: forces all media access through the API; no path for a client to bypass proximity validation or issue tokens to others. Revisit if: need for resumable downloads forces a change (signed URLs have short TTL); mitigation exists — re-issue mid-download on expiry.

**DEC-4 — Coordinates validated at request time, then discarded** · *Decided*

`/scan` and `/unlock` endpoints take `(lat, lng, accuracy_m)`, validate against drop point, return teaser or media URLs, discard the location input. No request log contains coordinates. Why: stateless; no "location history" attack surface; simplifies privacy posture. CI gate enforces: no endpoint handler may persist a coordinate. Revisit if: need for abuse detection requires retaining IPs + coordinates (unlikely; IP + timestamp + user_id suffices for rate limiting).

**DEC-5 — Asymmetric proximity bubbles (own vs. others)** · *Decided*

Own memories: base 25m + up to 75m accuracy cushion. Others' memories: base 20m + up to 25m, AND rejected if accuracy > 50m. Why: owner gets false-positive forgiveness (inaccurate GPS won't lock them out); others' privacy is protected (no "close enough from across the street"). Tunable via config table. Revisit if: real-world testing shows the numbers wrong; otherwise locked.

**DEC-6 — Server-side dwell for non-owned unlocks (two-check rule)** · *Decided (new mechanism)*

Non-owned memory unlock requires two passing proximity checks ≥20s apart. Owned memories skip this (false positives harmless). Why: makes scripted drive-by unlocks materially harder without burdening honest users (already standing there). Implemented via `presence_ping` upsert with TTL. Revisit if: user feedback shows false negatives (e.g., GPS jitter causes legit unlocks to fail); fallback is to increase dwell window or remove this check.

**DEC-7 — iOS 17+ as minimum** · *Decided*

Gains `@Observable`, `CLMonitor`, modern MapKit, App Attest. Why: iOS 17+ covers the overwhelming majority of active iOS devices by 2026; avoids framework cruft. Revisit only if beta surfaces a meaningful iOS 16 cohort.

**DEC-8 — SwiftUI + MVVM, no TCA** · *Decided*

App state is simple; framework tax compounds for a solo builder. Module seams (`LocationEngine`, `APIClient`, `WanderFeature`) provide structure. Revisit if: multi-step composed drops + offline queues + live co-presence start causing bugs that unidirectional architecture would prevent.

**DEC-9 — Apple MapKit, no Mapbox at launch** · *Decided*

Integrated into iOS 17+; adequate for v1. Styling needs met via overlays + custom annotation rendering. Why: zero external dependency, no cost, no API key in the app. Mapbox custom styling (Wander atmospheric basemap) can be replicated via MapKit overlays + gradient views. Revisit if: custom styling requirements exceed overlay complexity or user feedback demands a specific map vendor feature.

**DEC-10 — Five drop methods (V1–V5) with separate code paths** · *Decided*

Each (Pin, Treasure Chest, Import, Note in a Bottle, Prompt) has distinct UX, privacy, and composition rules. Why: clarity; prevents feature creep in a single picker; seals/conditions are opt-in, not default. Revisit if: three+ of these methods prove unused in beta (deprioritize the least-used).

**DEC-11 — V3 (Import) is private-only; elevation forbidden** · *Decided*

Camera roll imports cannot be shared as friends/public without owner performing a live drop at that location. Why: imported memories have EXIF GPS (which user may not have actively chosen to share); fresh drop proves intent. Revisit if: this rule frustrates users (e.g., old photos they genuinely want to share); fallback is to allow elevation after 24h or with explicit consent flow.

**DEC-12 — CSAM scanning mandatory at upload** · *Decided*

Hash-matching day-one. Vendor selection (PhotoDNA/Thorn/Hive) open; apply in M0. Why: legal + brand obligation; lead time is the long pole. Revisit: never; this is non-negotiable.

**DEC-13 — APNs direct, no OneSignal/FCM middleware in Phase 1** · *Decided*

iOS-only. Token-based auth. Why: fewer dependencies, lower cost, full control over notification content. Revisit at Phase 2 (Android) or if notification volume exceeds APNs reasonable limits (unlikely).

**DEC-14 — StoreKit 2 for in-app purchases** · *Decided*

Platform IAP rules apply; no external purchase steering. Premium features: seals (age-based, atmospheric, recurring), vault, replies. Why: lowest friction, best compliance, user expectations. Revisit if: feature scope requires subscriptions (currently transactional; V1 is mostly free).

**DEC-15 — Warmth cue is non-directional by design** · *Decided (privacy-critical)*

Screen-edge ambient gradient + haptic on coarse-zone entry. No arrow, compass, or direction indicator. Why: directional cue enables triangulation (user walks legs, watches gradient rise/fall, back-solves the location without proximity check). Non-directional cue leaks only "something is here," which the device already knew (coarse zone). Enforced by what the client *doesn't render*, not what the server withholds. Revisit: never; this is a privacy boundary.

**DEC-16 — Geohash precision 5 (~4.9 × 4.9 km cells) for coarse zones** · *Decided*

Why: simple; prefixes are in spec; generated on-device for background detection. Revisit if: H3 or adaptive precision becomes necessary (unlikely pre-Phase 3).

**DEC-17 — `presence_pings` as UNLOGGED table with TTL** · *Decided (revised)*

Upsert (`memory_id`, `user_id`, `last_seen_at`) with ~3min TTL. No coordinates stored; only the boolean outcome of a proximity check. Scheduled purge job keeps the table empty at steady state. Why: avoids tuple churn and WAL pressure on a regular table without WebSocket complexity (Supabase Realtime Presence upgrade path). Revisit to Realtime Presence if: live "N of M here" UX is pulled out of tabled features.

**DEC-18 — Cooldown window per memory (discoverable_after)** · *Decided*

Owner sets cooldown duration at drop; memory becomes discoverable only after duration elapsed. Why: prevents discovery immediately after drop; adds time-delta to the emotional weight. Default: 24h (tunable). Revisit if: user feedback shows people want zero delay for certain use cases.

---

## Phase 1 constraints

**DEC-19 — Phase 1 is photos-only; video deferred to Phase 2** · *Decided (clarification)*

Photo EXIF stripping via `ImageIO` is synchronous and fast. Video metadata stripping requires `AVAssetExportSession` (async, memory-heavy). Requirements already had video as "Should," not "Must." Revisit: not necessary; video lands in Phase 2 with a dedicated background export pipeline.

**DEC-20 — Phase 1 is single-user complete; no friends graph, no summons** · *Decided*

Shippable standalone. Friends/recipients land in Phase 2. Why: reduces surface for beta, proves core loop first. Revisit: locked until Phase 2 is planned.

**DEC-21 — Phase 1 background detection is own-memories-only** · *Decided*

Significant-change + region monitoring for user's own pins. Others' memories surfaced only in foreground. Why: eliminates complexity of background scan calls for others' content; no edge cases around coarse-zone permission; sufficient for MVP. Phase 2+ adds others' memories via coarse zones. Revisit: fixed for Phase 1; Phase 2 scope locked.

---

## Safety & anti-spoofing

**DEC-22 — App Attest is a feature-flagged gate, not hard** · *Decided*

Apple's attestation service can outage. Server-side flag (`app_attest_required`) on scan/unlock/drop allows instant bypass. Bypass is audit-logged, operational action (not silent). Why: resilience; Apple downtime won't lock users out. Monitoring: flag state checked continuously. Revisit: locked; this is the right resilience pattern.

**DEC-23 — Simulated-location rejection, accuracy sanity, no velocity/teleport detection** · *Decided*

Client: reject drops if `sourceInformation.isSimulatedBySoftware = true`. Server: accuracy must be >0, <1000m; timestamp within clock skew. Velocity detection rejected (requires movement trail → privacy violation). Compensating control: server-side dwell (two checks). Why: teleport detection needs a location history, which violates SEC-LOC-1. Accepted residual risk for Phase 1 (private-only); **must revisit before Phase 3** (public content). Revisit trigger: Phase 3 public memories + integrity requirements.

**DEC-24 — No jailbreak detection** · *Leaning*

Not implemented yet. Why: jailbreak detection is fragile, cat-and-mouse, and provides marginal security benefit on top of App Attest. Revisit if: abuse patterns surface that jailbreak detection would mitigate (unlikely for location-gated content).

---

## Operational & cost decisions

**DEC-25 — API hosting: initial estimate, review at Phase 2** · *Open*

Stateless REST API can run on a small managed instance ($100–200/mo). Scaling trigger: QPS exceeds 100 (unlikely pre-Phase 2). Revisit at Phase 2 if load testing shows different; likely remains sub-100 QPS indefinitely (location queries are O(n) neighbors, not O(all memories)).

**DEC-26 — S3 cost ceiling: 30% of infra spend → escalate to CDN** · *Decided*

If storage/egress exceeds 30% of monthly bill, migrate to R2/S3+CDN. Extraction path is clean: API already issues signed URLs; bucket swap is opaque to client. Revisit trigger: egress bill alert.

**DEC-27 — Analytics: TelemetryDeck (privacy-first)** · *Leaning*

Consistent with privacy-first brand promise. No user-level tracking. Alternative: PostHog (more power, more data gravity). Final decision at M0 (low stakes).

**DEC-28 — CI/migrations: local PostgreSQL + `psql` scripts** · *Leaning*

Simplest setup for solo builder. Flyway or Liquibase considered and rejected (overkill; psql + Git is sufficient). Revisit if: schema complexity or team size reaches 3+ people.

---

## Spec drift resolved by this plan

Items this plan adds that the product spec should absorb:

- DEC-6: two-check dwell rule for non-owned unlocks
- DEC-11: V3 (Import) private-only rule
- DEC-17: `presence_pings` ephemeral-state exception
- DEC-23: simulated-location + accuracy sanity checks
- DEC-9: MapKit as launch choice (open in product spec)

---

**DEC-29 — Offline-but-near UX: show warmth cue, surface "need a signal" message, withhold pin** · *Decided*

When device is inside a coarse zone (data pre-fetched) but lacks connectivity to call `/unlock`, the warmth cue persists and the app surfaces: "There's something here. You'll need a signal to open it." The exact pin location is not revealed. Why: coarse zones are pre-fetched on every successful scan, so offline-in-zone state requires no new infrastructure. Withholding the pin preserves the proximity invariant without requiring a server round-trip. Revisit if: user testing shows this message is confusing or users interpret it as a bug.

---

## Decisions pending

**Open — CSAM scanning vendor selection** · *Not blocking design*

Candidates: Microsoft PhotoDNA Cloud, Thorn Safer, Hive. Pipeline is vendor-agnostic (webhook flips `scan_status`). Action item: apply in M0.

**Tabled — Rich "N of M here" co-presence UX** · *Phase 2+ decision*

Shows progress to participants only (e.g., "2 of 3 here"); delight + slight presence leak. Requires WebSocket or poll-based UX; currently deferred. Revisit in Phase 2 if: co-presence seals prove popular and UNLOGGED table polling is insufficient for responsiveness.

**Tabled — Velocity/teleport detection for Phase 3** · *Must revisit pre-Phase 3*

Public-content integrity is higher stakes. Requires movement trail (position history + timestamps). Accepted residual risk for Phase 1 (private-only). Revisit decision at Phase 3 kickoff with: (a) measured abuse rate in private content, (b) cost of position trail (storage, privacy exposure), (c) alternative anti-spoof mechanisms.

---

## Revisions from external review

*[Document any external feedback that changes decisions — from product, security, or technical review.]*

---

## Decisions log conventions

- **Decided** = your call; explicit veto path is to communicate override.
- **Leaning** = 80% confident; open to pushback with data.
- **Open** = genuinely ambiguous; waiting on more information (beta feedback, tech spike, etc.).
- **Tension** = two principles in conflict; resolution documented and accepted.
- **Tabled** = deliberately deferred (usually to a later phase); revisit trigger stated.

Revisit triggers are the only reason to re-open a decision. Otherwise, decisions are treated as locked.
