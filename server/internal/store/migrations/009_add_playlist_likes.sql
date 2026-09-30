-- A shared playlist is link-only unless its owner makes it public; only
-- public ones are listed for everyone to discover. It only matters while
-- the playlist is shared, and unsharing resets it.
ALTER TABLE playlists ADD COLUMN IF NOT EXISTS is_public boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS playlists_public_idx
    ON playlists (updated_at DESC, id) WHERE is_public AND share_token IS NOT NULL;

-- One like per user per playlist; the primary key makes liking idempotent.
-- Likes go with the playlist or the user when either is deleted. While a
-- playlist is unshared its likes are kept but can't be seen or added.
CREATE TABLE IF NOT EXISTS playlist_likes (
    playlist_id uuid NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (playlist_id, user_id)
);

CREATE INDEX IF NOT EXISTS playlist_likes_user_idx ON playlist_likes (user_id);
