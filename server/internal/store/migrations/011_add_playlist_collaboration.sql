-- A collaborative playlist has a collaboration token: anyone signed in who
-- opens its link joins as a member and can add tracks from their own
-- library. NULL means nobody can join; a new token stops the old link.
ALTER TABLE playlists ADD COLUMN IF NOT EXISTS collab_token text UNIQUE;

-- Members of a playlist besides its owner. A track in a playlist stays owned
-- by whoever added it, so it counts against their quota. When a member
-- leaves or is removed, their tracks leave the playlist with them.
CREATE TABLE IF NOT EXISTS playlist_members (
    playlist_id uuid NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (playlist_id, user_id)
);

CREATE INDEX IF NOT EXISTS playlist_members_user_idx ON playlist_members (user_id);
