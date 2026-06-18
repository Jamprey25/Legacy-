-- 0009_imports.sql
-- Import idempotency table. Stores the result of POST /v1/memories/import keyed by
-- (user_id, idempotency_key). Replaying the same key returns the cached result without
-- re-inserting memories. See api-contract.md §5.

BEGIN;

CREATE TABLE imports (
    id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    idempotency_key  text        NOT NULL,
    result_json      jsonb       NOT NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),

    UNIQUE (user_id, idempotency_key)
);

CREATE INDEX imports_user_idx ON imports (user_id);

COMMIT;
