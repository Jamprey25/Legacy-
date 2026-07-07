-- 0015_friends_graph.sql
-- Phase 2 social: mutual-connection friends graph (completes schema-phone-verification;
-- phone_verifications + memory_recipients shipped in 0014_summons_preview.sql).
--
-- Canonical row ordering: user_a < user_b (one row per pair, enforced by CHECK).
-- requested_by records direction so "accept" semantics are unambiguous.

BEGIN;

CREATE TABLE IF NOT EXISTS friends_graph (
    user_a       uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b       uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status       text        NOT NULL DEFAULT 'pending'
                             CHECK (status IN ('pending', 'accepted', 'rejected')),
    requested_by uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at   timestamptz NOT NULL DEFAULT now(),
    responded_at timestamptz,

    PRIMARY KEY (user_a, user_b),
    CONSTRAINT friends_canonical_order CHECK (user_a < user_b),
    CONSTRAINT requested_by_is_member  CHECK (requested_by IN (user_a, user_b))
);

-- Reverse lookups: "who are user_b's friends" without a seq scan.
CREATE INDEX IF NOT EXISTS friends_graph_user_b_idx ON friends_graph(user_b);

-- Recipient eligibility checks join memory_recipients by phone at scan/unlock time.
CREATE INDEX IF NOT EXISTS memory_recipients_phone_idx ON memory_recipients(phone_e164);

COMMIT;
