package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type TrackStatus string

const (
	TrackPending TrackStatus = "pending"
	TrackReady   TrackStatus = "ready"
)

var (
	ErrQuotaExceeded  = errors.New("storage quota exceeded")
	ErrTooManyPending = errors.New("too many pending uploads")
)

type Track struct {
	ID          string
	OwnerID     string
	Status      TrackStatus
	Title       string
	Artist      *string
	Album       *string
	DurationMS  *int32
	StorageKey  string
	ContentType string
	SizeBytes   int64
	// Source is "upload" for the app, or the bot provider that imported it.
	Source    string
	CreatedAt time.Time
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
	// Source defaults to "upload".
	Source string
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

const (
	// pendingCleanupLock serializes cleaners across API instances while leaving
	// ordinary track reads and writes unaffected.
	pendingCleanupLock int64 = 7_310_076
)

const trackColumns = `id::text, owner_id::text, status, title, artist, album, duration_ms,
	storage_key, content_type, size_bytes, source, created_at`

func scanTrack(row pgx.Row) (Track, error) {
	var t Track
	err := row.Scan(&t.ID, &t.OwnerID, &t.Status, &t.Title, &t.Artist, &t.Album, &t.DurationMS,
		&t.StorageKey, &t.ContentType, &t.SizeBytes, &t.Source, &t.CreatedAt)
	return t, err
}

// ReservePending atomically checks the owner's total reserved bytes and active
// pending count before inserting a track. The owner-scoped advisory lock makes
// concurrent API instances unable to race past either limit.
func (t *Tracks) ReservePending(
	ctx context.Context,
	ownerID string,
	track NewTrack,
	maxOwnerBytes int64,
	maxPending int,
) (Track, error) {
	var reserved Track
	err := pgx.BeginFunc(ctx, t.pool, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx,
			`SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, ownerID,
		); err != nil {
			return err
		}
		var usedBytes int64
		var pending int
		if err := tx.QueryRow(ctx, `
			SELECT COALESCE(SUM(size_bytes), 0)::bigint,
			       COUNT(*) FILTER (WHERE status = 'pending')::integer
			FROM tracks
			WHERE owner_id::text = $1
		`, ownerID).Scan(&usedBytes, &pending); err != nil {
			return err
		}
		if pending >= maxPending {
			return ErrTooManyPending
		}
		if usedBytes > maxOwnerBytes || track.SizeBytes > maxOwnerBytes-usedBytes {
			return ErrQuotaExceeded
		}
		var err error
		reserved, err = createTrack(ctx, tx, ownerID, track, TrackPending)
		return err
	})
	return reserved, err
}

// Create inserts a track whose object is already in storage.
func (t *Tracks) Create(ctx context.Context, ownerID string, track NewTrack) (Track, error) {
	return createTrack(ctx, t.pool, ownerID, track, TrackReady)
}

type rowQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

func createTrack(ctx context.Context, query rowQuerier, ownerID string, track NewTrack, status TrackStatus) (Track, error) {
	source := track.Source
	if source == "" {
		source = "upload"
	}
	return scanTrack(query.QueryRow(ctx, `
		WITH new_id AS (SELECT gen_random_uuid() AS id)
		INSERT INTO tracks (id, owner_id, status, title, artist, album, duration_ms, storage_key, content_type, size_bytes, source)
		SELECT new_id.id, $1::uuid, $9, $2, $3, $4, $5,
		       'users/' || $1::text || '/tracks/' || new_id.id::text || '/' || $6::text, $7, $8, $10
		FROM new_id
		RETURNING `+trackColumns,
		ownerID, track.Title, track.Artist, track.Album, track.DurationMS,
		track.FileName, track.ContentType, track.SizeBytes, string(status), source,
	))
}

// UsageForOwner returns all bytes reserved by ready and pending tracks.
// It intentionally matches the quota calculation in ReservePending.
func (t *Tracks) UsageForOwner(ctx context.Context, ownerID string) (int64, error) {
	var usedBytes int64
	err := t.pool.QueryRow(ctx, `
		SELECT COALESCE(SUM(size_bytes), 0)::bigint
		FROM tracks
		WHERE owner_id::text = $1
	`, ownerID).Scan(&usedBytes)
	return usedBytes, err
}

func (t *Tracks) ListForOwner(ctx context.Context, ownerID string) ([]Track, error) {
	rows, err := t.pool.Query(ctx,
		`SELECT `+trackColumns+` FROM tracks WHERE owner_id::text = $1 AND status = 'ready'
		 ORDER BY created_at DESC, id`,
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

// MarkReady flips the owner's pending track to ready.
func (t *Tracks) MarkReady(ctx context.Context, ownerID, trackID string) (Track, error) {
	track, err := scanTrack(t.pool.QueryRow(ctx,
		`UPDATE tracks SET status = 'ready'
		 WHERE id::text = $1 AND owner_id::text = $2
		 RETURNING `+trackColumns,
		trackID, ownerID))
	if errors.Is(err, pgx.ErrNoRows) {
		return Track{}, ErrNotFound
	}
	return track, err
}

// Delete removes the owner's track row.
func (t *Tracks) Delete(ctx context.Context, ownerID, trackID string) error {
	tag, err := t.pool.Exec(ctx,
		`DELETE FROM tracks WHERE id::text = $1 AND owner_id::text = $2`, trackID, ownerID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// CleanupStalePending removes one bounded batch of abandoned reservations.
//
// A transaction-scoped advisory lock makes this safe across API instances. The
// object is removed before its row; if storage fails, the transaction rolls
// back and a later run retries the same row. Removing an already-missing object
// must be treated as success by remove.
func (t *Tracks) CleanupStalePending(
	ctx context.Context,
	before time.Time,
	limit int,
	remove func(context.Context, string) error,
) (int, error) {
	removed := 0
	err := pgx.BeginFunc(ctx, t.pool, func(tx pgx.Tx) error {
		var acquired bool
		if err := tx.QueryRow(ctx,
			`SELECT pg_try_advisory_xact_lock($1)`, pendingCleanupLock,
		).Scan(&acquired); err != nil {
			return err
		}
		if !acquired {
			return nil
		}

		rows, err := tx.Query(ctx, `
			SELECT `+trackColumns+`
			FROM tracks
			WHERE status = 'pending' AND created_at < $1
			ORDER BY created_at, id
			FOR UPDATE SKIP LOCKED
			LIMIT $2
		`, before, limit)
		if err != nil {
			return err
		}
		stale := make([]Track, 0, limit)
		for rows.Next() {
			track, err := scanTrack(rows)
			if err != nil {
				rows.Close()
				return err
			}
			stale = append(stale, track)
		}
		if err := rows.Err(); err != nil {
			rows.Close()
			return err
		}
		rows.Close()

		for _, track := range stale {
			if err := remove(ctx, track.StorageKey); err != nil {
				return fmt.Errorf("remove stale upload object: %w", err)
			}
			if _, err := tx.Exec(ctx,
				`DELETE FROM tracks WHERE id = $1 AND status = 'pending'`, track.ID,
			); err != nil {
				return err
			}
			removed++
		}
		return nil
	})
	return removed, err
}
