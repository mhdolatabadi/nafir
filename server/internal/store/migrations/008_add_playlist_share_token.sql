-- A shared playlist has a share token: anyone signed in who has its link can
-- view the playlist and play its tracks. NULL means private. Turning sharing
-- off clears it, so old links stop working; turning it on again makes a new one.
ALTER TABLE playlists ADD COLUMN IF NOT EXISTS share_token text UNIQUE;
