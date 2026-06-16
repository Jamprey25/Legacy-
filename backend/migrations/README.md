# Migrations

Plain `psql` + Git (DEC-28). Numbered, append-only, run in order. No Flyway/Liquibase.

## Run

```bash
# all migrations against a local db
for f in backend/migrations/0*.sql; do psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$f"; done
```

Each file is wrapped in `BEGIN/COMMIT` and is idempotent-safe to author but **not** re-runnable (no `IF NOT EXISTS` on tables) — they run once, in order, tracked by filename. CI runs the full chain against a fresh Postgres on every PR.

## Privacy gate (CI)

A CI step greps every migration for forbidden columns in log/event tables:

```bash
! grep -nEi '(lat|lng|longitude|latitude|geohash)' backend/migrations/0005_audit_log.sql
```

No coordinate may ever land in `audit_log`. See `engineering-plan.md §17`.

## Order

| File | Adds |
|---|---|
| 0001 | `users`, `sessions` |
| 0002 | `memories` (immutable drop point, geohash index) |
| 0003 | `seals`, `conditions` (fallback NOT NULL invariant) |
| 0004 | `finds`, `presence_pings` (UNLOGGED) |
| 0005 | `audit_log` (no coordinates, ever) |
| 0006 | `config` (tunable bubbles/cooldown) |
