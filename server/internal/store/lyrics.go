package store

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mhdolatabadi/nafir/server/internal/lyrics"
)

// Lyrics caches each track's LRCLIB lyrics; it implements lyrics.Cache.
// Callers check the user may play the track before reading its lyrics.
type Lyrics struct {
	pool *pgxpool.Pool
}

func NewLyrics(pool *pgxpool.Pool) *Lyrics {
	return &Lyrics{pool: pool}
}

func (l *Lyrics) Lyrics(ctx context.Context, trackID string) (lyrics.Entry, error) {
	var (
		e        lyrics.Entry
		id       *int64
		names    [3]*string
		duration *float64
	)
	err := l.pool.QueryRow(ctx, `
		SELECT track_id::text, match_key, found, lrclib_id, track_name, artist_name, album_name,
		       duration_seconds, instrumental, plain_lyrics, synced_lyrics, chosen, fetched_at, expires_at
		FROM track_lyrics WHERE track_id::text = $1
	`, trackID).Scan(&e.TrackID, &e.MatchKey, &e.Found, &id, &names[0], &names[1], &names[2],
		&duration, &e.Record.Instrumental, &e.Record.PlainLyrics, &e.Record.SyncedLyrics,
		&e.Chosen, &e.FetchedAt, &e.ExpiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return lyrics.Entry{}, lyrics.ErrNotCached
	}
	if err != nil {
		return lyrics.Entry{}, err
	}
	if id != nil {
		e.Record.ID = *id
	}
	for i, into := range []*string{&e.Record.TrackName, &e.Record.ArtistName, &e.Record.AlbumName} {
		if names[i] != nil {
			*into = *names[i]
		}
	}
	if duration != nil {
		e.Record.Duration = *duration
	}
	return e, nil
}

func (l *Lyrics) SaveLyrics(ctx context.Context, e lyrics.Entry) error {
	var id *int64
	var names [3]*string
	var duration *float64
	r := e.Record
	if e.Found {
		id, duration = &r.ID, &r.Duration
		names = [3]*string{&r.TrackName, &r.ArtistName, &r.AlbumName}
	} else {
		r = lyrics.Record{}
	}
	_, err := l.pool.Exec(ctx, `
		INSERT INTO track_lyrics (track_id, match_key, found, lrclib_id, track_name, artist_name,
			album_name, duration_seconds, instrumental, plain_lyrics, synced_lyrics, chosen,
			fetched_at, expires_at)
		VALUES ($1::text::uuid, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
		ON CONFLICT (track_id) DO UPDATE SET
			match_key = EXCLUDED.match_key, found = EXCLUDED.found, lrclib_id = EXCLUDED.lrclib_id,
			track_name = EXCLUDED.track_name, artist_name = EXCLUDED.artist_name,
			album_name = EXCLUDED.album_name, duration_seconds = EXCLUDED.duration_seconds,
			instrumental = EXCLUDED.instrumental, plain_lyrics = EXCLUDED.plain_lyrics,
			synced_lyrics = EXCLUDED.synced_lyrics, chosen = EXCLUDED.chosen,
			fetched_at = EXCLUDED.fetched_at, expires_at = EXCLUDED.expires_at
	`, e.TrackID, e.MatchKey, e.Found, id, names[0], names[1], names[2], duration,
		r.Instrumental, r.PlainLyrics, r.SyncedLyrics, e.Chosen && e.Found, e.FetchedAt, e.ExpiresAt)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23503" {
		// The track was deleted while its lyrics were looked up.
		return nil
	}
	return err
}
