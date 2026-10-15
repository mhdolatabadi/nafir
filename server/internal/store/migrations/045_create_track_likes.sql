-- Likes on tracks (#284): one per listener and track, so liking again
-- changes nothing. A store song is liked through the copy the listener
-- reached; its count is the distinct listeners who liked any of its
-- copies. Likes go with the track or the listener's account.
CREATE TABLE IF NOT EXISTS track_likes (
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    track_id uuid NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, track_id)
);

CREATE INDEX IF NOT EXISTS track_likes_track_idx ON track_likes (track_id);
CREATE INDEX IF NOT EXISTS track_likes_user_recent_idx ON track_likes (user_id, created_at DESC);
