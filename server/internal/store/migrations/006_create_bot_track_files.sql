-- The file ID a messenger assigned to a track the bot uploaded, so sending
-- the same track again reuses it instead of uploading the audio again.
CREATE TABLE IF NOT EXISTS bot_track_files (
    provider text NOT NULL,
    track_id uuid NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    file_id text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (provider, track_id)
);
