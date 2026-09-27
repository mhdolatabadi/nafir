CREATE TABLE playlists (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name text NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 200),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX playlists_owner_updated_idx
    ON playlists (owner_id, updated_at DESC, id);

CREATE TABLE playlist_tracks (
    playlist_id uuid NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    track_id uuid NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    position integer NOT NULL CHECK (position >= 0),
    added_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (playlist_id, track_id),
    UNIQUE (playlist_id, position)
);

CREATE INDEX playlist_tracks_track_idx ON playlist_tracks (track_id);
