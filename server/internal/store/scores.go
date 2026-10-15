package store

import (
	"context"
)

// RecordStorePlay counts one play of a listed store song by listener, at
// most once per listener, song and day; replays the same day change
// nothing. A song that left the store is not counted.
func (c *Catalog) RecordStorePlay(ctx context.Context, entryID, listener string) error {
	_, err := c.pool.Exec(ctx, `
		INSERT INTO store_plays (entry_id, listener) VALUES ($1::text::uuid, $2)
		ON CONFLICT DO NOTHING
	`, entryID, listener)
	return ignoreDeletedTrack(err)
}

// trendingDays is how far back trending looks; trendingHalfLife how fast
// an old like or play fades, in days.
const (
	trendingDays     = 14
	trendingHalfLife = 3.0
)

// RefreshScores recomputes every grouped song's popular score (all-time
// distinct likers across its copies plus plays) and trending score (the
// same within trendingDays, each weighted by its age with a
// trendingHalfLife-day half-life), and forgets plays older than a year.
func (c *Catalog) RefreshScores(ctx context.Context) error {
	if _, err := c.pool.Exec(ctx, `
		WITH likes AS (
			SELECT et.entry_id, tl.user_id, min(tl.created_at) AS at
			FROM store_entry_tracks et JOIN track_likes tl ON tl.track_id = et.track_id
			GROUP BY et.entry_id, tl.user_id
		), events AS (
			SELECT entry_id, at FROM likes
			UNION ALL SELECT entry_id, played_at FROM store_plays
		), scores AS (
			SELECT e.id AS entry_id,
				count(ev.at)::float8 AS popular,
				COALESCE(sum(CASE WHEN ev.at > now() - make_interval(days => $1)
					THEN power(0.5, extract(epoch FROM now() - ev.at) / 86400 / $2) END), 0) AS trending
			FROM store_entries e LEFT JOIN events ev ON ev.entry_id = e.id
			GROUP BY e.id
		)
		INSERT INTO store_scores (entry_id, popular, trending, updated_at)
		SELECT entry_id, popular, trending, now() FROM scores
		ON CONFLICT (entry_id) DO UPDATE SET popular = EXCLUDED.popular,
			trending = EXCLUDED.trending, updated_at = now()
	`, trendingDays, trendingHalfLife); err != nil {
		return ignoreDeletedTrack(err)
	}
	_, err := c.pool.Exec(ctx, `DELETE FROM store_plays WHERE day < current_date - 365`)
	return err
}

// StoreRanking orders store songs for StoreRanked.
type StoreRanking string

const (
	RankPopular  StoreRanking = "popular"
	RankTrending StoreRanking = "trending"
)

// StoreRanked lists listed songs with a score above zero, best first, by
// the cached scores; ties go to the entry id so the order is stable.
func (c *Catalog) StoreRanked(ctx context.Context, ranking StoreRanking, limit, offset int) ([]StoreEntry, bool, error) {
	column := "s.popular"
	if ranking == RankTrending {
		column = "s.trending"
	}
	rows, err := c.pool.Query(ctx, `
		WITH `+liveEntries+`
		SELECT live.entry_id, live.copies, live.hidden_at IS NOT NULL, `+liveTrackColumns+`
		FROM live JOIN store_scores s ON s.entry_id::text = live.entry_id
		WHERE `+column+` > 0
		ORDER BY `+column+` DESC, live.entry_id
		LIMIT $2 OFFSET $3
	`, false, limit+1, offset)
	if err != nil {
		return nil, false, err
	}
	entries, err := scanStoreEntries(rows)
	if err != nil {
		return nil, false, err
	}
	if len(entries) > limit {
		return entries[:limit], true, nil
	}
	return entries, false, nil
}
