-- 0014_muted_zones.sql
-- User-defined zones where proximity push notifications are suppressed.
-- When a scan fires a push, the backend checks if the scanning user's current
-- coordinates fall inside any of their muted zones and skips the push if so.

BEGIN;

CREATE TABLE muted_zones (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    lat         double precision NOT NULL,
    lng         double precision NOT NULL,
    -- radius in metres: 100m (one block) → 5000m (neighbourhood)
    radius_m    integer     NOT NULL DEFAULT 500
                            CHECK (radius_m BETWEEN 100 AND 5000),
    label       text,       -- optional user-supplied name e.g. "Home", "Work"
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX muted_zones_user_idx ON muted_zones (user_id);

COMMIT;
