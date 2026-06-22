-- 0005_audit_log.sql
-- Structured event log. NEVER contains coordinates. The CI privacy gate greps migrations
-- and insert sites to enforce that raw GPS fields never appear here. IP + user_id +
-- timestamp is sufficient for rate-limit abuse detection.

BEGIN;

CREATE TABLE audit_log (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event       text        NOT NULL,         -- 'auth.login','memory.drop','scan','unlock','attest.bypass',...
    actor_id    uuid        REFERENCES users(id) ON DELETE SET NULL,
    request_id  text,
    ip          inet,                          -- allowed; coordinates are not
    metadata    jsonb       NOT NULL DEFAULT '{}'::jsonb,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX audit_log_actor_idx ON audit_log (actor_id, created_at);
CREATE INDEX audit_log_event_idx ON audit_log (event, created_at);

COMMENT ON TABLE audit_log IS
    'Append-only event log. INVARIANT: no raw position data columns or values, ever. Enforced by CI privacy gate.';

COMMIT;
