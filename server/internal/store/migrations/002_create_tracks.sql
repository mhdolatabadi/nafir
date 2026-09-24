CREATE TABLE tracks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title text NOT NULL,
    artist text,
    album text,
    duration_ms integer CHECK (duration_ms >= 0),
    storage_key text NOT NULL UNIQUE,
    content_type text NOT NULL,
    size_bytes bigint NOT NULL CHECK (size_bytes >= 0),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX tracks_owner_created_idx ON tracks (owner_id, created_at DESC);
