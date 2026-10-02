-- Optimistic concurrency for metadata edits: every successful edit bumps the
-- version, and an edit based on an older version is rejected instead of
-- silently overwriting someone else's change. Existing tracks start at 1.
ALTER TABLE tracks
  ADD COLUMN metadata_version bigint NOT NULL DEFAULT 1,
  ADD COLUMN metadata_updated_at timestamptz,
  ADD CONSTRAINT tracks_metadata_version_positive CHECK (metadata_version > 0);
