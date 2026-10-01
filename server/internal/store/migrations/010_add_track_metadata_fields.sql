ALTER TABLE tracks
  ADD COLUMN file_name text,
  ADD COLUMN album_artist text,
  ADD COLUMN composer text,
  ADD COLUMN genre text,
  ADD COLUMN year integer,
  ADD COLUMN track_number integer,
  ADD COLUMN disc_number integer,
  ADD COLUMN comment text;

UPDATE tracks
SET file_name = regexp_replace(storage_key, '^.*/', '')
WHERE file_name IS NULL;

ALTER TABLE tracks
  ALTER COLUMN file_name SET NOT NULL,
  ADD CONSTRAINT tracks_file_name_not_blank CHECK (btrim(file_name) <> ''),
  ADD CONSTRAINT tracks_year_range CHECK (year IS NULL OR (year BETWEEN 0 AND 9999)),
  ADD CONSTRAINT tracks_track_number_positive CHECK (track_number IS NULL OR track_number > 0),
  ADD CONSTRAINT tracks_disc_number_positive CHECK (disc_number IS NULL OR disc_number > 0);
