-- 0003_seals_conditions.sql
-- One seal and/or one condition per memory. The critical invariant: a condition row
-- CANNOT exist without a fallback timestamp (NOT NULL). This makes "no user can ever
-- be stranded behind an unsatisfiable condition" a structural guarantee, not app logic.

BEGIN;

CREATE TABLE seals (
    memory_id  uuid PRIMARY KEY REFERENCES memories(id) ON DELETE CASCADE,
    seal_type  text NOT NULL
               CHECK (seal_type IN ('none','fixed_date','duration','age_based','recurring')),
    -- type-specific config:
    --   fixed_date: { open_at }
    --   duration:   { locked_hours }
    --   age_based:  { recipient_dob, open_at_age }
    --   recurring:  { window_start, window_duration_hours, next_open }
    config     jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE conditions (
    memory_id             uuid PRIMARY KEY REFERENCES memories(id) ON DELETE CASCADE,
    condition_type        text NOT NULL
                          CHECK (condition_type IN
                              ('time_of_day','season','weather','co_presence','long_absence','nth_return')),
    config                jsonb NOT NULL DEFAULT '{}'::jsonb,

    -- THE constraint. No condition may exist without a fallback open time.
    condition_time_fallback timestamptz NOT NULL,

    created_at            timestamptz NOT NULL DEFAULT now()
);

COMMIT;
