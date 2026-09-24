-- Uploads create a pending row first; it becomes ready once the object is verified.
ALTER TABLE tracks
    ADD COLUMN status text NOT NULL DEFAULT 'ready' CHECK (status IN ('pending', 'ready'));
