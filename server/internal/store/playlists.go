package store

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Playlist struct {
	ID        string
	OwnerID   string
	Name      string
	CreatedAt time.Time
	UpdatedAt time.Time
	Tracks    []Track
}

type Playlists struct {
	pool *pgxpool.Pool
}

func NewPlaylists(pool *pgxpool.Pool) *Playlists {
	return &Playlists{pool: pool}
}

func (p *Playlists) ListForOwner(ctx context.Context, ownerID string) ([]Playlist, error) {
	rows, err := p.pool.Query(ctx, `
		SELECT id::text, owner_id::text, name, created_at, updated_at
		FROM playlists
		WHERE owner_id::text = $1
		ORDER BY updated_at DESC, id
	`, ownerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	playlists := []Playlist{}
	for rows.Next() {
		var playlist Playlist
		if err := rows.Scan(&playlist.ID, &playlist.OwnerID, &playlist.Name, &playlist.CreatedAt, &playlist.UpdatedAt); err != nil {
			return nil, err
		}
		playlists = append(playlists, playlist)
	}
	return playlists, rows.Err()
}

func (p *Playlists) ForOwner(ctx context.Context, ownerID, playlistID string) (Playlist, error) {
	var playlist Playlist
	err := p.pool.QueryRow(ctx, `
		SELECT id::text, owner_id::text, name, created_at, updated_at
		FROM playlists
		WHERE id::text = $1 AND owner_id::text = $2
	`, playlistID, ownerID).Scan(
		&playlist.ID, &playlist.OwnerID, &playlist.Name, &playlist.CreatedAt, &playlist.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return Playlist{}, ErrNotFound
	}
	if err != nil {
		return Playlist{}, err
	}

	rows, err := p.pool.Query(ctx, `
		SELECT `+trackColumns+`
		FROM playlist_tracks pt
		JOIN tracks ON tracks.id = pt.track_id
		WHERE pt.playlist_id = $1::uuid AND tracks.owner_id::text = $2 AND tracks.status = 'ready'
		ORDER BY pt.position
	`, playlistID, ownerID)
	if err != nil {
		return Playlist{}, err
	}
	defer rows.Close()
	playlist.Tracks = []Track{}
	for rows.Next() {
		track, err := scanTrack(rows)
		if err != nil {
			return Playlist{}, err
		}
		playlist.Tracks = append(playlist.Tracks, track)
	}
	return playlist, rows.Err()
}

func (p *Playlists) Create(ctx context.Context, ownerID, name string) (Playlist, error) {
	var playlist Playlist
	err := p.pool.QueryRow(ctx, `
		INSERT INTO playlists (owner_id, name)
		VALUES ($1::uuid, $2)
		RETURNING id::text, owner_id::text, name, created_at, updated_at
	`, ownerID, name).Scan(
		&playlist.ID, &playlist.OwnerID, &playlist.Name, &playlist.CreatedAt, &playlist.UpdatedAt,
	)
	return playlist, err
}

func (p *Playlists) Rename(ctx context.Context, ownerID, playlistID, name string) (Playlist, error) {
	var playlist Playlist
	err := p.pool.QueryRow(ctx, `
		UPDATE playlists SET name = $3, updated_at = now()
		WHERE id::text = $1 AND owner_id::text = $2
		RETURNING id::text, owner_id::text, name, created_at, updated_at
	`, playlistID, ownerID, name).Scan(
		&playlist.ID, &playlist.OwnerID, &playlist.Name, &playlist.CreatedAt, &playlist.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return Playlist{}, ErrNotFound
	}
	return playlist, err
}

func (p *Playlists) ReplaceTracks(ctx context.Context, ownerID, playlistID string, trackIDs []string) error {
	return pgx.BeginFunc(ctx, p.pool, func(tx pgx.Tx) error {
		var exists bool
		if err := tx.QueryRow(ctx, `
			SELECT EXISTS (
				SELECT 1 FROM playlists WHERE id::text = $1 AND owner_id::text = $2
			)
		`, playlistID, ownerID).Scan(&exists); err != nil {
			return err
		}
		if !exists {
			return ErrNotFound
		}

		if _, err := tx.Exec(ctx, `DELETE FROM playlist_tracks WHERE playlist_id = $1::uuid`, playlistID); err != nil {
			return err
		}
		for position, trackID := range trackIDs {
			tag, err := tx.Exec(ctx, `
				INSERT INTO playlist_tracks (playlist_id, track_id, position)
				SELECT $1::uuid, id, $4
				FROM tracks
				WHERE id::text = $2 AND owner_id::text = $3 AND status = 'ready'
			`, playlistID, trackID, ownerID, position)
			if err != nil {
				return err
			}
			if tag.RowsAffected() == 0 {
				return ErrNotFound
			}
		}
		_, err := tx.Exec(ctx, `UPDATE playlists SET updated_at = now() WHERE id = $1::uuid`, playlistID)
		return err
	})
}

func (p *Playlists) Delete(ctx context.Context, ownerID, playlistID string) error {
	tag, err := p.pool.Exec(ctx, `
		DELETE FROM playlists WHERE id::text = $1 AND owner_id::text = $2
	`, playlistID, ownerID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
