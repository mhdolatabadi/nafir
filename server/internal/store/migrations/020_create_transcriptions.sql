CREATE TABLE track_transcriptions (
    track_id uuid PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
    state text NOT NULL CHECK (state IN ('queued', 'processing', 'done', 'failed')),
    plain_text text NOT NULL DEFAULT '',
    synced_text text NOT NULL DEFAULT '',
    updated_at timestamptz NOT NULL DEFAULT now()
);
