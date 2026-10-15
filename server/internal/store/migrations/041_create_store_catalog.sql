-- The public store (#243): every song in a public playlist, listed once.
-- An entry is one song; store_entry_tracks maps each copy of it (a track in
-- someone's public playlist) to the entry. Copies are grouped by acoustic
-- fingerprint, else by normalized title and artist with a close duration.
-- The mapping is only a grouping: what is listed and which copy plays is
-- decided live from the copies that are still in a public playlist, so a
-- track that leaves every public playlist leaves the store at once. The
-- entry keeps a representative fingerprint, so a hidden entry stays hidden
-- when a new copy of the same song arrives.
CREATE TABLE IF NOT EXISTS store_entries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title_key text NOT NULL,
    duration_seconds double precision,
    points bytea,
    hidden_at timestamptz,
    hidden_by uuid,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS store_entries_title_key_idx ON store_entries (title_key);
CREATE INDEX IF NOT EXISTS store_entries_duration_idx
    ON store_entries (duration_seconds) WHERE points IS NOT NULL;

CREATE TABLE IF NOT EXISTS store_entry_tracks (
    track_id uuid PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
    entry_id uuid NOT NULL REFERENCES store_entries(id) ON DELETE CASCADE,
    added_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS store_entry_tracks_entry_idx ON store_entry_tracks (entry_id);
