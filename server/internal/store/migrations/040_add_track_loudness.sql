-- ReplayGain read from each track's own tags (#253). NULL means the file
-- carries none; loudness_scanned_at stays NULL until the scanner has read
-- the file, so existing tracks are backfilled by the same job.
ALTER TABLE tracks
    ADD COLUMN replaygain_track_gain_db double precision,
    ADD COLUMN replaygain_track_peak double precision,
    ADD COLUMN replaygain_album_gain_db double precision,
    ADD COLUMN replaygain_album_peak double precision,
    ADD COLUMN loudness_scanned_at timestamptz;

CREATE INDEX tracks_loudness_unscanned ON tracks (created_at)
    WHERE status = 'ready' AND loudness_scanned_at IS NULL;
