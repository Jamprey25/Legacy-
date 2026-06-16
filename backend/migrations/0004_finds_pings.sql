-- 0004_finds_pings.sql
-- finds: durable record of each unlock (drives nth_return + long_absence).
-- presence_pings: ephemeral co-presence state. UNLOGGED (no WAL) because the table
-- is empty at steady state — a purge job removes rows past TTL. Stores only the boolean
-- outcome of a proximity check, never coordinates. (DEC-17)

BEGIN;

CREATE TABLE finds (
    id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    memory_id uuid        NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
    user_id   uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    found_at  timestamptz NOT NULL DEFAULT now()
);

-- nth_return counts rows; long_absence reads MAX(found_at). Both keyed by (memory,user).
CREATE INDEX finds_memory_user_idx ON finds (memory_id, user_id, found_at);

CREATE UNLOGGED TABLE presence_pings (
    memory_id    uuid        NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
    user_id      uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (memory_id, user_id)         -- upsert target
);

-- purge job: DELETE FROM presence_pings WHERE last_seen_at < now() - interval '3 minutes';
CREATE INDEX presence_pings_ttl_idx ON presence_pings (last_seen_at);

COMMIT;
