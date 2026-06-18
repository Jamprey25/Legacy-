# Legacy — Claude Code (Backend)

You own **backend API work** in this monorepo. Cursor owns **iOS**. Joseph relays between sessions.

## Before every session

Read and follow **`docs/engineering/AGENT_WORKFLOW.md`** (mandatory checklist).

Minimum reads:

1. `tasks.json` — open `decisions[]`, **open discussion threads** (`question`/`concern`/`idea`), tasks with `owner: "backend"`
2. **Reply** to any thread where `needs: "backend"` or iOS raised something you have not answered
3. `docs/engineering/collab-log.md` — last 2 entries + **iOS → Backend** section
4. `docs/engineering/api-contract.md` — if changing endpoints
5. `git status` — especially `backend/**`

## Your scope

- **Edit freely:** `backend/**`, migrations, `api-contract.md` (when endpoints change)
- **Append only:** `collab-log.md`, `tasks.json` (tasks, threads, responses)
- **Avoid without collab-log entry:** `ios/**`

## Cross-agent feedback (required)

- **Raise** `concern` / `question` / `idea` items in `tasks.json` when iOS needs your input or you see risk
- **Reply** to threads directed at backend before ending session — append `responses[]` with `"author": "backend"`
- Do not use chat for agent-to-agent questions — dashboard threads are canonical

## When you ship API work

1. Update `api-contract.md`
2. Append **Backend → iOS** bullets in `collab-log.md`
3. Mark related tasks `done` in `tasks.json`
4. Commit with `backend:` prefix

## When you need Joseph

Document first in `tasks.json` → `decisions[]` with `options[]` (or a thread with `needs: "joseph"`). Do not ask in chat until written.

## End of session

Append `[backend → all] YYYY-MM-DD` block to `collab-log.md` per `AGENT_WORKFLOW.md`. Confirm all open threads needing backend have replies.

## Truth hierarchy

`tasks.json` > `collab-log.md` > `api-contract.md` > chat > Ruflo memory
