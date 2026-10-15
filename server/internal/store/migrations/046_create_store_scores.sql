-- Popular and trending store songs (#284). A play is counted once per
-- listener, song and day: listener is "u:" and the account id, or "a:" and
-- a keyed hash of the visitor's address that changes every day, so no
-- address is stored. store_scores caches each listed song's scores,
-- refreshed in the background: popular is all-time likes plus plays,
-- trending the same over the last two weeks with a three-day half-life.
CREATE TABLE IF NOT EXISTS store_plays (
    entry_id uuid NOT NULL REFERENCES store_entries(id) ON DELETE CASCADE,
    listener text NOT NULL,
    day date NOT NULL DEFAULT current_date,
    played_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (entry_id, listener, day)
);

CREATE INDEX IF NOT EXISTS store_plays_day_idx ON store_plays (day);

CREATE TABLE IF NOT EXISTS store_scores (
    entry_id uuid PRIMARY KEY REFERENCES store_entries(id) ON DELETE CASCADE,
    popular double precision NOT NULL DEFAULT 0,
    trending double precision NOT NULL DEFAULT 0,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS store_scores_popular_idx ON store_scores (popular DESC, entry_id);
CREATE INDEX IF NOT EXISTS store_scores_trending_idx ON store_scores (trending DESC, entry_id);
