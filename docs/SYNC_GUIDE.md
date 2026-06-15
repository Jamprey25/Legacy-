# Documentation Sync Guide

Quick reference for keeping `/docs/engineering/` and `/docs/product/` in sync with the live product at https://legacy-preview-rho.vercel.app/

---

## When to update

**Update `/docs/product/product-overview.md`:**
- New drop method added or existing method changes (V1–V5 flows)
- Feature set changes (Memory Lane, Wander, seals, conditions, replies, etc.)
- Pricing tiers or IAP offerings change
- Phase roadmap shifts (what ships in P1 vs. P2 vs. P3)
- Competitive positioning needs refresh
- Brand voice or messaging changes

**Update `/docs/engineering/engineering-plan.md`:**
- API endpoints added, removed, or signature changes
- Database schema additions (new tables, columns, constraints)
- Privacy invariants change
- Proximity bubble numbers change
- Anti-spoofing mechanisms added/removed
- Import clustering logic changes
- Background detection mechanism changes

**Update `/docs/engineering/architecture-decisions.md`:**
- A new decision is made (add with date and status)
- An existing decision changes status (Leaning → Decided, Tabled → Open, etc.)
- Revisit trigger is met; document the outcome
- Tension is resolved; document how
- External review surfaces new decisions

---

## Quick checklist before syncing docs

Before you ask me to update docs, ask yourself:

- [ ] Have I checked the website (https://legacy-preview-rho.vercel.app/) for the source of truth?
- [ ] Do the internal docs contradict the website? (If yes, website wins.)
- [ ] Has the engineering changed (API, DB schema, privacy model)? (If yes, update engineering-plan.md)
- [ ] Has the product changed (features, pricing, use cases)? (If yes, update product-overview.md)
- [ ] Has a decision been made or changed? (If yes, update architecture-decisions.md)

---

## How to ask for doc updates

**Example 1 — Feature shipped:**
> "We shipped co-presence seals (Phase 2). Add to engineering plan §13 (Seals & Conditions) and product overview §Premium features. Decision log: note DEC-17 (presence_pings) moved from Tabled to active."

**Example 2 — Architecture change:**
> "We switched from Supabase to REST API + Postgres. Update engineering plan §3 entirely, update decision log DEC-1, add DEC-[n] explaining REST choice."

**Example 3 — Pricing change:**
> "Changed Vault from $99/year to $149/year. Update product overview §Monetization table."

---

## Document structure

```
docs/
├── engineering/
│   ├── engineering-plan.md       (how it's built)
│   └── architecture-decisions.md (why decisions were made)
└── product/
    ├── product-overview.md       (what it does, positioning, pricing)
    └── [future: use-cases.md, security-posture.md, etc.]
```

---

## What's *not* in these docs (belongs elsewhere)

- **Git history & commits:** git log
- **Code patterns & conventions:** CLAUDE.md in the repo
- **Debugging notes:** GitHub issues or project management tool
- **Team decisions (non-engineering):** product decision log
- **Real-time sprint status:** task board or sprint notes
- **Code examples:** repository itself

These docs are high-level, living specifications. They should be read by:
- Future you (onboarding yourself to what you built)
- Me (context for why we're making engineering decisions)
- Anyone joining the project (here's the building blocks)

---

## Versioning

No explicit version numbers. The docs are "living." If you need to reference a specific point in time, refer to the git commit hash.

Sync date format: `YYYY-MM-DD` (included in each doc's header after "Last synced:").

---

## Examples of what changed (Memory Drop → Legacy)

| Document | Memory Drop | Legacy |
|---|---|---|
| **engineering-plan.md** | Supabase RPC + `SECURITY DEFINER` | REST API + stateless validation |
| **engineering-plan.md** | MapBox (custom styling) | MapKit + custom overlays |
| **engineering-plan.md** | 5 drop methods proposed | 5 drop methods final (V1–V5 named) |
| **product-overview.md** | "Memory Drop" | "Legacy" |
| **product-overview.md** | Pricing TBD | Specific tiers (Free, Premium $0.99–$9.99, Vault $99/yr, Institutional custom) |
| **product-overview.md** | Phase 2a uncertain | Phase 2 (Recipients → Friends → Vault) and Phase 3 (Public + Institutional) locked |
| **architecture-decisions.md** | DEC-1 (Supabase) | DEC-1 (REST API) + new decisions |

---

## Notes for continuous updates

When you say "update the docs to reflect X," I will:
1. Fetch the website if relevant (e.g., pricing, features)
2. Read the existing doc file
3. Update the specific sections affected
4. Update the "Last synced: YYYY-MM-DD" date
5. Point out what changed (so you can verify)

You don't need to enumerate every change; just tell me what changed and why, and I'll make the edits surgical.

---

Example:
```
You: "We're shipping Phase 2 recipients this week. Update the docs — add the summons flow, the phone ACL, and move recipients from 'Tabled' to active in the roadmap."

Me: [reads current docs] [fetches website for any context] [updates product-overview.md §Phase 2, engineering-plan.md §10, architecture-decisions.md §DEC-20 status] [shows you what changed]
```

That's it. Easy to keep in sync.
