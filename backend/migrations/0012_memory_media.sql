-- 0012_memory_media.sql
-- A memory holds MANY photos, not one. Until now a memory's media was a single
-- `media_key` on `memories` — so an imported visit of 200 photos collapsed to one image,
-- which "makes no human sense" (Joseph, session 11). This table holds the full set.
--
-- Design: the HERO photo stays denormalised on `memories` (media_key/thumbnail_key/
-- scan_status) so the discovery hot path + its partial index are untouched. `memory_media`
-- holds every photo (hero = position 0, mirrored). Reads (GET /:id, unlock) return the
-- ordered array; discovery/proximity keep reading the hero off `memories`.

BEGIN;

CREATE TABLE memory_media (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    memory_id     uuid        NOT NULL REFERENCES memories(id) ON DELETE CASCADE,

    -- 0 = hero (mirrors memories.media_key). Higher = additional photos in capture order.
    position      int         NOT NULL DEFAULT 0,

    media_type    text        NOT NULL DEFAULT 'photo'
                              CHECK (media_type IN ('photo', 'video')),
    media_key     text,                          -- set once the blob is uploaded
    thumbnail_key text,                          -- set post-clear, best-effort
    scan_status   text        NOT NULL DEFAULT 'pending'
                              CHECK (scan_status IN ('pending', 'clear', 'blocked')),
    created_at    timestamptz NOT NULL DEFAULT now(),

    UNIQUE (memory_id, position)
);

CREATE INDEX memory_media_memory_idx ON memory_media (memory_id, position);

-- Backfill: every existing memory's single media becomes its position-0 (hero) row, so
-- reads can switch to the array uniformly without special-casing pre-migration memories.
INSERT INTO memory_media (memory_id, position, media_type, media_key, thumbnail_key, scan_status)
SELECT id, 0, media_type, media_key, thumbnail_key, scan_status
FROM memories
WHERE media_key IS NOT NULL
  AND media_type IN ('photo', 'video');

COMMIT;
