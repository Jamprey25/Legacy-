-- 0013_user_display_name.sql
-- User-editable display name. NULL = fall back to email-derived name on the client.
-- Max 100 chars, trimmed server-side. Never used as an identity or auth field.

BEGIN;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS display_name text
        CHECK (char_length(display_name) <= 100);

COMMIT;
