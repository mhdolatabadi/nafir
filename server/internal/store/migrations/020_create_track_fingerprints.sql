-- Acoustic fingerprints for song identification (#210): Chromaprint's raw
-- fingerprint of each ready track, four little-endian bytes per item. A
-- row without points is a fingerprint still to compute or one that failed;
-- the worker retries it until attempts runs out. The row goes with its
-- track. The audio itself is only read, never changed.
CREATE TABLE IF NOT EXISTS track_fingerprints (
    track_id uuid PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
    points bytea,
    duration_seconds double precision,
    attempts integer NOT NULL DEFAULT 0,
    error text,
    -- A worker's lease; another may take over once it passes.
    claimed_until timestamptz,
    -- When a failed attempt may be retried.
    not_before timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS track_fingerprints_ready_idx
    ON track_fingerprints (track_id) WHERE points IS NOT NULL;
