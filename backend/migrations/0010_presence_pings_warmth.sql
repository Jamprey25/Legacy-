-- 0010_presence_pings_warmth.sql
-- Add warmth debounce state to presence_pings (q-warmth-temporal-debounce).
--
-- Policy (agreed with iOS 2026-06-18):
--   Upgrades (coarse→approaching→in_bubble) are emitted immediately.
--   Downgrades require the new lower band to hold for 2 consecutive scans ≥15s apart.
--   last_emitted_warmth = the band last sent on the wire to the client.
--   pending_downgrade_warmth = candidate lower band from the previous scan.
--   pending_downgrade_at = timestamp of that candidate scan.

BEGIN;

ALTER TABLE presence_pings
  ADD COLUMN last_emitted_warmth    text,
  ADD COLUMN pending_downgrade_warmth text,
  ADD COLUMN pending_downgrade_at   timestamptz;

COMMIT;
