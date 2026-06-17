-- 0008_rate_limits.sql
-- Fixed-window rate-limit counters. UNLOGGED (no WAL) because rows are ephemeral —
-- a purge job removes windows older than the longest configured window. Stores only
-- a bucket key (ip:<addr> or user:<uuid>), the window start, and a count. Never
-- coordinates. (rate-limiting task: "IP + user_id + timestamp sufficient.")
--
-- Atomic increment via INSERT ... ON CONFLICT DO UPDATE ... RETURNING count, so the
-- limit check is correct across concurrent Vercel Function instances (no shared memory).

BEGIN;

CREATE UNLOGGED TABLE rate_limits (
    bucket_key   text        NOT NULL,   -- "scan:user:<uuid>", "auth:ip:<addr>", etc.
    window_start timestamptz NOT NULL,   -- floor(now / window) — start of the fixed window
    count        integer     NOT NULL DEFAULT 0,
    PRIMARY KEY (bucket_key, window_start)
);

-- purge job: DELETE FROM rate_limits WHERE window_start < now() - interval '1 hour';
CREATE INDEX rate_limits_window_idx ON rate_limits (window_start);

COMMIT;
