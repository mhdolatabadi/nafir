package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Track struct {
	ID          string
	OwnerID     string
	Title       string
	Artist      *string
	Album       *string
	DurationMS  *int32
	StorageKey  string
	ContentType string
	SizeBytes   int64
	CreatedAt   time.Time
}

// NewTrack is what a caller supplies; the ID is chosen by the store so the
// storage key can include it.
type NewTrack struct {
	Title       string
	Artist      *string
	Album       *string
	DurationMS  *int32
	FileName    string
	ContentType string
	SizeBytes   int64
}

// StorageKey is the owner-scoped object path for a track.
func StorageKey(ownerID, trackID, fileName string) string {
	return fmt.Sprintf("users/%s/tracks/%s/%s", ownerID, trackID, fileName)
}

// Tracks always filters by owner: there is deliberately no method that reads
// a track without one.
type Tracks struct {
	pool *pgxpool.Pool
}

func NewTracks(pool *pgxpool.Pool) *Tracks {
	return &Tracks{pool: pool}
}

const trackColumns = `id::text, owner_id::text, title, artist, album, duration_ms,
	storage_key, content_type, size_bytes, created_at`

func scanTrack(row pgx.Row) (Track, error) {
	var t Track
	err := row.Scan(&t.ID, &t.OwnerID, &t.Title, &t.Artist, &t.Album, &t.DurationMS,
		&t.StorageKey, &t.ContentType, &t.SizeBytes, &t.CreatedAt)
	return t, err
}

func (t *Tracks) Create(ctx context.Context, ownerID string, track NewTrack) (Track, error) {
	return scanTrack(t.pool.QueryRow(ctx, `
		WITH new_id AS (SELECT gen_random_uuid() AS id)
		INSERT INTO tracks (id, owner_id, title, artist, album, duration_ms, storage_key, content_type, size_bytes)
		SELECT new_id.id, $1::uuid, $2, $3, $4, $5,
		       'users/' || $1::text || '/tracks/' || new_id.id::text || '/' || $6::text, $7, $8
		FROM new_id
		RETURNING `+trackColumns,
		ownerID, track.Title, track.Artist, track.Album, track.DurationMS,
		track.FileName, track.ContentType, track.SizeBytes,
	))
}

func (t *Tracks) ListForOwner(ctx context.Context, ownerID string) ([]Track, error) {
	rows, err := t.pool.Query(ctx,
		`SELECT `+trackColumns+` FROM tracks WHERE owner_id::text = $1 ORDER BY created_at DESC, id`,
		ownerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	tracks := []Track{}
	for rows.Next() {
		track, err := scanTrack(rows)
		if err != nil {
			return nil, err
		}
		tracks = append(tracks, track)
	}
	return tracks, rows.Err()
}

// ForOwner returns ErrNotFound both when the track does not exist and when it
// belongs to someone else, so callers cannot probe other users' track IDs.
func (t *Tracks) ForOwner(ctx context.Context, ownerID, trackID string) (Track, error) {
	track, err := scanTrack(t.pool.QueryRow(ctx,
		`SELECT `+trackColumns+` FROM tracks WHERE id::text = $1 AND owner_id::text = $2`,
		trackID, ownerID))
	if errors.Is(err, pgx.ErrNoRows) {
		return Track{}, ErrNotFound
	}
	return track, err
}
