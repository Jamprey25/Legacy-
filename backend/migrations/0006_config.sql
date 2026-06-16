-- 0006_config.sql
-- Tunable runtime config (proximity bubbles, cooldown defaults). Lets us adjust the
-- numbers from DEC-5 without a deploy. Single-row-per-key.

BEGIN;

CREATE TABLE config (
    key        text PRIMARY KEY,
    value      jsonb NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO config (key, value) VALUES
    ('proximity.own',    '{"base_m": 25, "accuracy_cushion_max_m": 75}'::jsonb),
    ('proximity.others', '{"base_m": 20, "accuracy_cushion_max_m": 25, "reject_above_accuracy_m": 50}'::jsonb),
    ('dwell',            '{"checks_required": 2, "min_gap_seconds": 20}'::jsonb),
    ('cooldown',         '{"default_hours": 24}'::jsonb),
    ('signed_url',       '{"put_ttl_minutes": 15, "get_ttl_minutes": 60}'::jsonb),
    ('co_presence',      '{"ping_ttl_seconds": 180, "unlock_window_minutes": 10}'::jsonb),
    ('public_age_min',   '16'::jsonb);

COMMIT;
