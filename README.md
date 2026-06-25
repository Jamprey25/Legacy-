# Legacy

**The places remember you.** Drop memories at GPS coordinates. Return to unlock them.

Product vision and positioning: [legacy-preview-rho.vercel.app](https://legacy-preview-rho.vercel.app)

---

## What this repo is

Legacy is a location-gated memory app. Photos and notes are dropped at real-world coordinates and can only be unlocked by physically returning to that place. The core invariant: **exact coordinates and media never reach a client before a server-side proximity check passes.**

This monorepo is split across two builders:

| Area | Owner | Stack |
|---|---|---|
| **iOS app** | Cursor | Swift / SwiftUI, iOS 17+, local SPM modules |
| **Backend API** | Claude Code | TypeScript/Node (Hono or Fastify) + PostgreSQL on Vercel |
| **Task dashboard** | Shared | Next.js on Vercel, reads `tasks.json` |

Coordination happens through shared repo docs (not chat memory):

- **`tasks.json`** — shared task list (status, owner, blockers). The [live dashboard](https://dashboard-two-orpin-63.vercel.app) auto-refreshes every 30s.
- **`docs/engineering/collab-log.md`** — cross-AI decisions, open questions, handoffs.
- **`docs/engineering/AGENT_WORKFLOW.md`** — **session start/end rituals**, edit boundaries, Joseph relay template. Both agents read this first.

**Process:** Decisions that need Joseph go in the collab log or `tasks.json` `decisions[]` *before* anyone asks him in chat. See **Working agreement** in `collab-log.md` and **Agent workflow** above.

Authoritative API shapes: **`docs/engineering/api-contract.md`**

---

## Quick start — iOS

**Requirements:** macOS with **Xcode 15+** (iOS 17 SDK), Apple Developer account for device builds.

```bash
# Open the app project (local package ref → ios/LegacyModules)
open ios/Legacy.xcodeproj
```

1. Select the **Legacy** scheme and an iOS 17+ simulator (or your device).
2. Set your **Development Team** in Signing & Capabilities.
3. Build and run (`⌘R`).

**Host-compile modules without Xcode UI** (CI / sanity check):

```bash
cd ios/LegacyModules && swift build
```

Unit tests require full Xcode:

```bash
cd ios/LegacyModules && swift test   # or xcodebuild test in Xcode
```

The app currently launches into an empty **Wander** map shell (M0 demo target).

**Recent (2026-06-25):** Memory Lane adds Places/Map browsing, search, unlock return narrative, client-side thumbnails, and a Phase 2 summons preview in Treasure Chest drops. See `collab-log.md` for the full roadmap batch.

---

## Quick start — backend

Backend is **in progress** (M0). Runtime is locked to **TypeScript/Node + `pg` on Vercel Functions**. Schema migrations live under `backend/migrations/`.

See `docs/engineering/engineering-plan.md` and `docs/engineering/api-contract.md` before implementing endpoints.

---

## Quick start — task dashboard

```bash
cd dashboard && npm install && npm run dev
```

Production: [dashboard-two-orpin-63.vercel.app](https://dashboard-two-orpin-63.vercel.app)

The dashboard now has two live views:
- **Delivery view** — tasks, blockers, milestones, decision queue.
- **Architecture view** — technical structure map (system topology, iOS module graph, and core runtime flows for drop/scan/unlock).
- **Architecture deep links** — each architecture node and flow card links to the corresponding repo module or engineering doc.

Optional link-root overrides for different forks/orgs:
- `NEXT_PUBLIC_REPO_WEB_ROOT` (default: `https://github.com/Jamprey25/Legacy-/tree/main`)
- `NEXT_PUBLIC_DOCS_WEB_ROOT` (default: `https://github.com/Jamprey25/Legacy-/blob/main`)

### Vercel setup (required — monorepo)

The Next.js app lives in **`dashboard/`**, not the repo root. In Vercel → Project → **Settings → General**:

| Setting | Value |
|---|---|
| **Root Directory** | `dashboard` |
| **Framework Preset** | Next.js |
| **Production Branch** | `main` |

If Root Directory is `.` (repo root), builds fail silently or never update — there is no root `package.json`.

After saving, open **Deployments** → **Redeploy** the latest `main` commit.

**Decisions:** When Claude/Cursor escalate something to you, it appears at the top of the dashboard with clickable **options**. Your choice is written to `tasks.json` (set `DECISIONS_SECRET` + `GITHUB_TOKEN` on Vercel; locally it updates `../tasks.json` without a token).

**Discussions:** Agents raise **questions, concerns, and ideas** in the same `decisions[]` list. They must reply to each other's open threads (`needs: "ios"` or `"backend"`) — see [`AGENT_WORKFLOW.md`](docs/engineering/AGENT_WORKFLOW.md).

---

## Repository layout

```
Legacy/
├── ios/                          # iOS app + SPM modules (Cursor)
│   ├── Legacy.xcodeproj
│   ├── LegacyApp/                # App target (@main)
│   └── LegacyModules/            # DesignSystem, APIClient, LocationEngine, features…
├── backend/                      # API + migrations (Claude Code)
├── dashboard/                    # Task board (Next.js)
├── docs/
│   ├── engineering/              # api-contract, engineering-plan, collab-log, TECHNICAL_INTERNAL
│   └── product/                  # product-overview
└── tasks.json                    # Shared task source of truth
```

---

## Privacy invariants (non-negotiable)

These apply to all iOS and backend work:

1. **Warmth cue is non-directional** — screen-edge ambient gradient only; no arrow, compass, or bearing (prevents triangulation).
2. **Never cache non-owned coordinates** on device. Own memory pins may be cached for offline Wander.
3. **Strip EXIF client-side** before any image leaves the device (`ImageIO` rewrite).
4. **Seal/condition evaluation is server-side only** at unlock time.
5. **Session token in Keychain only** — never UserDefaults or plain disk.

Full rationale: `docs/engineering/engineering-plan.md`, `docs/engineering/architecture-decisions.md`.

---

## Documentation

| Doc | Purpose |
|---|---|
| [Product overview](docs/product/product-overview.md) | What Legacy does, features, pricing |
| [Engineering plan](docs/engineering/engineering-plan.md) | Architecture, phases, privacy model |
| [API contract](docs/engineering/api-contract.md) | Exact request/response wire format |
| [Technical internal](docs/engineering/TECHNICAL_INTERNAL.md) | iOS module design, state, flows |
| [Agent workflow](docs/engineering/AGENT_WORKFLOW.md) | Claude + Cursor sync rituals, roles, handoffs |
| [Collab log](docs/engineering/collab-log.md) | Cross-AI decisions, brainstorm, **working agreement** |
| [Sync guide](docs/SYNC_GUIDE.md) | Product website ↔ internal docs (not agent sync) |

---

## License

TBD.
