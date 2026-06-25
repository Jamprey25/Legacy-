-- Phase 2 preview: phone verification + memory recipients + summons log.

CREATE TABLE IF NOT EXISTS phone_verifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  phone_e164 TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS phone_verifications_user_idx ON phone_verifications(user_id);

ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_e164 TEXT;

CREATE TABLE IF NOT EXISTS memory_recipients (
  memory_id UUID NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
  phone_e164 TEXT NOT NULL,
  invited_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (memory_id, phone_e164)
);

CREATE TABLE IF NOT EXISTS summons_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  memory_id UUID NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
  owner_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recipient_phone_e164 TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS summons_log_memory_idx ON summons_log(memory_id);
