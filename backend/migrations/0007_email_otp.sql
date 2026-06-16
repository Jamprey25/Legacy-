-- 0007_email_otp.sql
-- Email OTP codes. Codes are stored HASHED (sha-256), never plaintext. Single-use,
-- short-lived. A row is consumed (deleted) on successful verify; a purge job clears
-- expired rows. Send attempts are rate-limited at the API layer.

BEGIN;

CREATE TABLE email_otps (
    email       citext      NOT NULL,
    code_hash   text        NOT NULL,         -- sha-256 hex of the 6-digit code
    expires_at  timestamptz NOT NULL,
    attempts    int         NOT NULL DEFAULT 0,
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (email)                        -- one active code per email (upsert)
);

CREATE INDEX email_otps_expiry_idx ON email_otps (expires_at);

COMMIT;
