-- 0002_memories.sql
-- The memory drop point. Coordinates are immutable after insert (the only persisted
-- spatial data in the system). geohash stored at precision 9 (~4.8m) for proximity;
-- coarse zone = left(geohash, 5) (~4.9km, DEC-16). Prefix index serves both.

BEGIN;

CREATE TABLE memories (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id           uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- immutable drop point
    lat                double precision NOT NULL,
    lng                double precision NOT NULL,
    geohash            text        NOT NULL,         -- precision 9

    source             text        NOT NULL DEFAULT 'live'
                                   CHECK (source IN ('live', 'imported')),
    drop_method        text        NOT NULL DEFAULT 'pin'
                                   CHECK (drop_method IN ('pin','treasure_chest','import','note_bottle','prompt')),
    privacy_tier       text        NOT NULL DEFAULT 'private'
                                   CHECK (privacy_tier IN ('private','recipients','friends','public')),

    scan_status        text        NOT NULL DEFAULT 'pending'
                                   CHECK (scan_status IN ('pending','clear','blocked')),

    media_type         text        NOT NULL DEFAULT 'photo'
                                   CHECK (media_type IN ('photo','text','video')),
    media_key          text,                          -- S3 key; NULL for text-only (V4)
    thumbnail_key      text,                          -- set post-clear
    caption            text,
    teaser_text        text,

    discoverable_after timestamptz NOT NULL,          -- cooldown gate
    created_at         timestamptz NOT NULL DEFAULT now(),

    -- structural enforcement: imported memories can never be elevated past private.
    -- The API also returns 422 cannot_elevate_import, but this is the backstop.
    CONSTRAINT imported_is_private
        CHECK (source <> 'imported' OR privacy_tier = 'private'),

    -- photos/videos need a media key once cleared; text never does.
    CONSTRAINT text_has_no_media
        CHECK (media_type <> 'text' OR media_key IS NULL)
);

-- Proximity query: geohash prefix range scan. text_pattern_ops enables LIKE 'prefix%'.
CREATE INDEX memories_geohash_idx  ON memories (geohash text_pattern_ops);
CREATE INDEX memories_owner_idx    ON memories (owner_id);
-- Discovery eligibility hot path: cleared + cooldown elapsed.
CREATE INDEX memories_discovery_idx
    ON memories (geohash text_pattern_ops, discoverable_after)
    WHERE scan_status = 'clear';

COMMIT;
