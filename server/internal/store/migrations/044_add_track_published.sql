-- Single-track publish (#284): an owner may publish one track on its own,
-- not only through a public playlist. A published ready track is listed in
-- the store (#243) under the same deduplication; unpublishing takes it out
-- unless a public playlist still holds it. NULL means private.
ALTER TABLE tracks ADD COLUMN IF NOT EXISTS published_at timestamptz;

CREATE INDEX IF NOT EXISTS tracks_published_idx
    ON tracks (published_at) WHERE published_at IS NOT NULL;
