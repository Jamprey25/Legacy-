-- 0001_users_sessions.sql
-- Users + sessions. Session tokens are stateless JWTs (validated by signature/expiry),
-- so this `sessions` row is NOT consulted on the hot path — it exists for APNs token
-- storage and explicit revocation only. See api-contract.md §1.2.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS citext;     -- case-insensitive email

CREATE TABLE users (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dob           date        NOT NULL,
    email         citext      UNIQUE,
    apple_sub     text        UNIQUE,
    google_sub    text        UNIQUE,
    -- "adult" (16+) | "minor" (13-15, restricted). Under-13 is rejected at the API
    -- layer and never inserted. age_tier is set at signup and re-derivable from dob.
    age_tier      text        NOT NULL DEFAULT 'adult'
                              CHECK (age_tier IN ('adult', 'minor')),
    account_status text       NOT NULL DEFAULT 'active'
                              CHECK (account_status IN ('active', 'deleted')),
    created_at    timestamptz NOT NULL DEFAULT now(),
    deleted_at    timestamptz,

    -- at least one identity must be present
    CONSTRAINT users_has_identity
        CHECK (apple_sub IS NOT NULL OR google_sub IS NOT NULL OR email IS NOT NULL)
);

-- Devices / sessions: push tokens + App Attest binding + revocation.
CREATE TABLE sessions (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id         text        NOT NULL,
    apns_token        text,
    app_attest_key_id text,
    os_version        text,
    model             text,
    created_at        timestamptz NOT NULL DEFAULT now(),
    last_seen_at      timestamptz NOT NULL DEFAULT now(),
    revoked_at        timestamptz,

    UNIQUE (user_id, device_id)
);

CREATE INDEX sessions_user_idx ON sessions (user_id) WHERE revoked_at IS NULL;
CREATE INDEX sessions_apns_idx ON sessions (apns_token) WHERE apns_token IS NOT NULL;

COMMIT;
