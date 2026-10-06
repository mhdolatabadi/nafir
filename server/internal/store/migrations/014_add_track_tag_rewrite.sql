-- Embedded tag rewriting (#50). After a metadata edit the stored object is
-- rewritten in the background; storage_key keeps pointing at the old,
-- playable object until the new one is uploaded and verified.
--
-- tag_status:
--   original    the file's tags were never rewritten by Nafir
--   pending     an edit is waiting for (or in) a rewrite
--   written     the object's tags match metadata version tag_version
--   failed      rewriting gave up; tag_error says why
--   unsupported the format has no safe tag writer
ALTER TABLE tracks
  ADD COLUMN tag_status text NOT NULL DEFAULT 'original',
  ADD COLUMN tag_version bigint,
  ADD COLUMN tag_error text,
  ADD COLUMN tag_attempts integer NOT NULL DEFAULT 0,
  -- A worker's lease on the rewrite; another worker may take over after it.
  ADD COLUMN tag_claimed_until timestamptz,
  -- When a failed attempt may be retried.
  ADD COLUMN tag_not_before timestamptz,
  -- An object uploaded by a rewrite that has not replaced storage_key yet.
  -- After a crash it is moved to storage_garbage before the next attempt.
  ADD COLUMN pending_storage_key text,
  ADD CONSTRAINT tracks_tag_status_known
    CHECK (tag_status IN ('original', 'pending', 'written', 'failed', 'unsupported'));

CREATE INDEX tracks_tag_pending_idx ON tracks (tag_not_before) WHERE tag_status = 'pending';

-- Objects to delete once delete_after passes. A replaced object stays a
-- while so playback that already has a presigned URL can finish.
CREATE TABLE storage_garbage (
  key text PRIMARY KEY,
  reason text NOT NULL,
  delete_after timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX storage_garbage_due_idx ON storage_garbage (delete_after);
