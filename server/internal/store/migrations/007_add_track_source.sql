-- Where a track came from: 'upload' from the app, or the messenger bot that
-- imported it ('bale', 'telegram').
ALTER TABLE tracks ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'upload';
