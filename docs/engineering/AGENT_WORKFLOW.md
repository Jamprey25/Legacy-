# Agent Workflow — Claude Code + Cursor

**Purpose:** Keep backend (Claude Code) and iOS (Cursor) in sync without relying on chat memory.  
**Audience:** Both AI agents and Joseph (relay).  
**Last updated:** 2026-06-17

---

## Roles

| Agent | Primary owner | Stack | Typical tasks |
|---|---|---|---|
| **Claude Code** | `backend/**`, migrations, API contract | TypeScript/Node, Hono, PostgreSQL | Endpoints, auth, proximity/seal eval, DB schema |
| **Cursor** | `ios/**` | Swift/SwiftUI, SPM modules | Features, APIClient, UI, iOS tests |
| **Either** | `docs/**`, root `tasks.json`, `dashboard/**` | — | Decisions, task board, cross-cutting docs |
| **Joseph** | Product calls, credentials, manual QA | — | Dashboard decisions, `.env` secrets, Xcode smoke tests |

Joseph relays between sessions when agents do not share memory. **The repo is the bus — chat is not.**

---

## Source of truth (read in this order)

1. **`tasks.json`** — task status, blockers, `decisions[]`, `manualTests[]`
2. **`docs/engineering/collab-log.md`** — cross-agent notes, open questions, handoffs
3. **`docs/engineering/api-contract.md`** — wire format (backend owns changes; iOS codes to it)
4. **`docs/engineering/engineering-plan.md`** — architecture, privacy invariants, phases
5. **Chat / Ruflo AgentDB** — hints only; never authoritative

**Ruflo:** Optional orchestration memory (`namespace: legacy`). **Do not** treat Ruflo tasks as a second task board. `tasks.json` wins.

---

## Session start (both agents — mandatory)

Run this at the **beginning of every session** before writing code:

```bash
git fetch origin && git status && git log -5 --oneline
```

Then read (skim if familiar, read fully if stale):

- [ ] `tasks.json` → `meta.lastUpdated`, open `decisions[]`, your owned tasks (`owner: "ios"` or `"backend"`)
- [ ] **`tasks.json` → open discussion threads** — every item with `kind` in `question` | `concern` | `idea` and `status: "open"` (see [Dashboard discussions](#dashboard-discussions-concerns-ideas-questions))
- [ ] **Reply to threads that need you** — any open thread where `needs` is your role, or where the other agent raised something you have not answered yet
- [ ] `docs/engineering/collab-log.md` → **last 2 dated entries** (`[ios → all]`, `[backend → all]`, handoffs)
- [ ] Relevant directional section: **Backend → iOS** (Cursor) or **iOS → Backend** (Claude)
- [ ] If touching API: `docs/engineering/api-contract.md`
- [ ] `git status` in **your** tree — note uncommitted work from the other agent

**Do not** assume the other side's chat context. If it is not in `collab-log.md` or `tasks.json`, it did not happen.

---

## Dashboard discussions (concerns, ideas, questions)

The [task dashboard](https://dashboard-two-orpin-63.vercel.app) surfaces **`tasks.json` → `decisions[]`** threads. These are the **primary channel** for cross-agent feedback — not chat.

### Required behavior

| When | Action |
|---|---|
| **Session start** | Read all open `question` / `concern` / `idea` threads; **reply** to any where `needs` is you or you have not yet responded |
| **During work** | If you hit ambiguity, a privacy worry, or a design tradeoff → **add a thread** (or reply to an existing one) **before** coding around it |
| **Session end** | No open thread directed at you may lack your reply; mark resolved when consensus is reached |

**Encouraged:** Raise at least one `idea` or `concern` per milestone when you see drift risk, UX friction, or a better approach — even if non-blocking.

### Thread kinds

| `kind` | Use for | `needs` usually |
|---|---|---|
| `question` | Factual/API ambiguity — needs an answer | `backend` or `ios` |
| `concern` | Risk, privacy, or invariant worry — needs acknowledgment + plan | other agent or `joseph` |
| `idea` | Non-urgent improvement — brainstorm, may become a task | `joseph` or other agent |
| `decision` | Joseph must pick (`options[]`) | `joseph` |
| `blocker` | Hard stop until resolved | varies |

### Add a new thread (agents edit `tasks.json` directly)

```json
{
  "id": "concern-short-slug",
  "kind": "concern",
  "title": "One-line summary",
  "status": "open",
  "raisedBy": "ios",
  "needs": "backend",
  "detail": "Context, why it matters, what you are worried about.",
  "blocks": ["optional-task-id"],
  "responses": []
}
```

Use `raisedBy` / `needs`: `"ios"` | `"backend"` | `"joseph"`.

### Reply to a thread (required when `needs` is you)

Append to the item's `responses[]` in `tasks.json` (same commit as your code or docs):

```json
{
  "author": "backend",
  "text": "Direct answer or agreement/disagreement with reasoning.",
  "date": "2026-06-17"
}
```

Also add a **one-line pointer** in `collab-log.md` (Open questions or directional section) so handoff readers see it — the dashboard thread remains canonical.

### Resolve a thread

When both agents agree (Joseph optional unless `needs: "joseph"`):

1. Set `"status": "resolved"` on the item
2. Optionally add a final `responses[]` entry summarizing the outcome
3. If it changes behavior → update `api-contract.md`, tasks, or `architecture-decisions.md` as needed

Joseph can also resolve via the dashboard UI; agents read the result next session.

### Examples in repo

- `q-app-attest-nullability` — iOS question → backend replied → Joseph agreed
- `concern-warmth-scalar` — backend concern → iOS replied → resolved
- `idea-openapi-contract` — backend idea → iOS replied (still open)

**Do not** discuss cross-agent feedback only in chat. If it is not in `tasks.json` `decisions[]`, the other agent will not see it on boot.

---

## Edit boundaries

| Path | Owner | Other agent may edit if… |
|---|---|---|
| `ios/**` | Cursor | Collab-log entry + Joseph OK (rare) |
| `backend/**` | Claude Code | Same |
| `docs/engineering/api-contract.md` | Claude Code (primary) | Cursor proposes via collab-log; Claude applies |
| `docs/engineering/collab-log.md` | Either | Append only — do not delete others' entries |
| `tasks.json` | Either | Update statuses for tasks you completed; do not remove others' tasks |
| `dashboard/**` | Either | Prefer one agent per feature; note in collab-log |

**Shared-file collisions:** If both agents need the same file (e.g. route + client for one endpoint), **one side ships first**, the other reads git diff + collab-log before continuing. Never overwrite silently.

---

## During work

### Cross-agent feedback (required)

1. **Check** open dashboard threads (`question` / `concern` / `idea`) before and during implementation
2. **Reply** to any thread where `needs` matches your role — same session if possible
3. **Raise** new threads when you find contract gaps, privacy worries, or ideas worth discussing
4. **Do not** wait for Joseph to relay agent-to-agent questions — use `needs: "backend"` or `needs: "ios"`

See [Dashboard discussions](#dashboard-discussions-concerns-ideas-questions) above for JSON shapes.

### Decisions that need Joseph

Follow **Working agreement** in `collab-log.md`:

1. Write to **Open questions**, **Brainstorm**, or `tasks.json` → `decisions[]` with `options[]`
2. Do **not** ask Joseph in chat until documented
3. Wait for dashboard decision or Joseph relay

### API or schema changes (backend)

1. Update `api-contract.md` in the **same session**
2. Append **Backend → iOS** bullet in `collab-log.md` (what shipped, what iOS should do)
3. Update related `tasks.json` task status

### iOS contract consumption (Cursor)

1. Code to `api-contract.md` — switch on `error.code`, never `message`
2. If contract is ambiguous, add `tasks.json` → `decisions[]` thread (`kind: "question"`, `needs: "backend"`) **and** append **iOS → Backend** in collab-log; do not guess

### Commits

- Commit **your tree** when a logical unit is done (tests green for that area)
- Message prefix: `ios:` / `backend:` / `dashboard:` / `docs:`
- Do not commit secrets (`.env`, credentials)

---

## Session end (both agents — mandatory)

Before ending, append a block to `collab-log.md`:

```markdown
## [ROLE → all] YYYY-MM-DD — Short title

**Shipped:**
- bullet list

**Tasks marked done:** `task-id-1`, `task-id-2`

**Blocked on Joseph / other agent:**
- bullet list

**Uncommitted / branch:** `branch-name`, files or "clean on main"

**Next session picks up:**
1. numbered list
```

Also:

- [ ] Update `tasks.json` — set `status` for completed tasks; bump `meta.lastUpdated`
- [ ] **Discussion duty** — replied to all open threads where `needs` is you; raised threads for anything left unresolved with the other agent
- [ ] Add `manualTests[]` items if Joseph should verify in Xcode
- [ ] If end-of-day: add `## 📅 End-of-day handoff — YYYY-MM-DD` summary

---

## `tasks.json` update rules

| Action | Who | Rule |
|---|---|---|
| Mark task `done` | Agent that shipped it | Same session as code |
| Add new task | Either | `owner`, `milestone`, clear `title` |
| Open decision | Either | `decisions[]` with `options[]`, `blocks[]` |
| **Raise question/concern/idea** | Either | **Required** when cross-agent input needed; set `needs` |
| **Reply to thread** | Agent named in `needs` (or other side if you have context) | **Required** before session end; append `responses[]` |
| Resolve thread | Either agent (consensus) or Joseph (dashboard) | Set `status: "resolved"` |
| Close decision | Joseph (dashboard) | Agents read result next session |

Task `owner` values: `"ios"` | `"backend"` | `"either"` | `"joseph"`

---

## Joseph relay template

Paste into a **new** Claude or Cursor chat when switching agents:

```
Legacy handoff — read before coding:

1. Follow docs/engineering/AGENT_WORKFLOW.md (session start checklist).
2. Read tasks.json — open decisions + discussion threads (question/concern/idea); reply where needs is you.
3. Read last 2 entries in docs/engineering/collab-log.md.
4. [Optional] Focus this session: <one sentence goal>.
5. [Optional] Blockers: <credentials, decisions pending>.
```

---

## Quick reference — doc purposes

| Doc | Agent sync? | Purpose |
|---|---|---|
| **This file** | ✅ | Roles, rituals, boundaries |
| `collab-log.md` | ✅ | Decisions, handoffs, directional notes |
| `tasks.json` | ✅ | Task board + Joseph decisions |
| `api-contract.md` | ✅ | Wire format |
| `SYNC_GUIDE.md` | ❌ | Product website ↔ internal docs (not agent sync) |
| `TECHNICAL_INTERNAL.md` | Partial | iOS/backend implementation depth |

---

## Pedagogical note

Two stateless agents sharing one repo behave like **microservices without a message bus**. `tasks.json` + `collab-log.md` are the bus; **`decisions[]` threads are the request/response channel** between agents. Session-start **subscribe**, in-session **reply**, and session-end **publish** are required; otherwise each chat reinvents context and sync fails.
