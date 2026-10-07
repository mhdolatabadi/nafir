-- Lyrics looked up from LRCLIB (#211), cached per track: found lyrics and
-- "not found" alike, until expires_at. match_key fingerprints the title,
-- artist and album they were looked up for, so editing any of them makes
-- the entry stale. The row goes with its track.
CREATE TABLE IF NOT EXISTS track_lyrics (
    track_id uuid PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
    match_key text NOT NULL,
    found boolean NOT NULL,
    lrclib_id bigint,
    track_name text,
    artist_name text,
    album_name text,
    duration_seconds double precision,
    instrumental boolean NOT NULL DEFAULT false,
    plain_lyrics text,
    synced_lyrics text,
    -- The track's owner picked this LRCLIB entry by hand.
    chosen boolean NOT NULL DEFAULT false,
    fetched_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    CONSTRAINT track_lyrics_found_has_id CHECK (NOT found OR lrclib_id IS NOT NULL)
);
