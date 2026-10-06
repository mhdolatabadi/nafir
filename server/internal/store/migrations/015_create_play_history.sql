-- Recently played: one row per meaningful listen. A row goes with its
-- user, its track, or the collaborative playlist it was played through,
-- so deleting any of them leaves no trace. Only the newest entries per
-- user are kept; the store trims the rest on every insert.
CREATE TABLE IF NOT EXISTS play_history (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    track_id uuid NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    -- Set only for someone else's track, played as a member of this
    -- playlist; the user's own tracks need no context.
    playlist_id uuid REFERENCES playlists(id) ON DELETE CASCADE,
    played_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS play_history_user_played_idx
    ON play_history (user_id, played_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS play_history_track_idx ON play_history (track_id);
CREATE INDEX IF NOT EXISTS play_history_playlist_idx
    ON play_history (playlist_id) WHERE playlist_id IS NOT NULL;
