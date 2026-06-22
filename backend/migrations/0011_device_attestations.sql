BEGIN;

-- Stores the per-device App Attest credential key, registered once at device setup.
-- key_id  = base64url(SHA256(credentialPublicKey)) — Apple's DCAppAttestService keyId.
-- public_key_spki = DER-encoded SubjectPublicKeyInfo (EC P-256) extracted from credCert.
-- counter tracks assertion sign-count for replay detection.
-- receipt is kept for optional Apple fraud-detection API (DEC-29).
CREATE TABLE IF NOT EXISTS device_attestations (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id     text        NOT NULL,
  key_id        text        NOT NULL UNIQUE,
  public_key_spki bytea     NOT NULL,
  receipt       bytea       NOT NULL,
  environment   text        NOT NULL CHECK (environment IN ('production', 'development')),
  counter       integer     NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS device_attestations_device_id_idx
  ON device_attestations (device_id);

COMMIT;
