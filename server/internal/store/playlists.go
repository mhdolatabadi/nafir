package store

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Playlist struct {
	ID      string
	OwnerID string
	Name    string
	// ShareToken is set while the playlist is shared.
	ShareToken *string
	CreatedAt  time.Time
	UpdatedAt  time.Time
	Tracks     []Track
}

// ErrShareTokenTaken means a newly drawn share token collided; draw again.
var ErrShareTokenTaken = errors.New("share token is already in use")

// playlistColumnNames is the one list of columns scanPlaylist reads, in order.
var playlistColumnNames = []string{"id::text", "owner_id::text", "name", "share_token", "created_at", "updated_at"}

var (
	playlistColumns          = strings.Join(playlistColumnNames, ", ")
	qualifiedPlaylistColumns = qualifyColumns("playlists", playlistColumnNames)
)

func scanPlaylist(row pgx.Row) (Playlist, error) {
	var p Playlist
	err := row.Scan(&p.ID, &p.OwnerID, &p.Name, &p.ShareToken, &p.CreatedAt, &p.UpdatedAt)
	return p, err
}

type Playlists struct {
	pool *pgxpool.Pool
}

func NewPlaylists(pool *pgxpool.Pool) *Playlists {
	return &Playlists{pool: pool}
}

func (p *Playlists) ListForOwner(ctx context.Context, ownerID string) ([]Playlist, error) {
	rows, err := p.pool.Query(ctx, `
		SELECT `+playlistColumns+`
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
		playlist, err := scanPlaylist(rows)
		if err != nil {
			return nil, err
		}
		playlists = append(playlists, playlist)
	}
	return playlists, rows.Err()
}

func (p *Playlists) ForOwner(ctx context.Context, ownerID, playlistID string) (Playlist, error) {
	playlist, err := scanPlaylist(p.pool.QueryRow(ctx, `
		SELECT `+playlistColumns+`
		FROM playlists
		WHERE id::text = $1 AND owner_id::text = $2
	`, playlistID, ownerID))
	if errors.Is(err, pgx.ErrNoRows) {
		return Playlist{}, ErrNotFound
	}
	if err != nil {
		return Playlist{}, err
	}
	playlist.Tracks, err = p.tracks(ctx, playlist)
	return playlist, err
}

// tracks lists the playlist's ready tracks in order. Only the owner's own
// tracks can be in a playlist, and this checks it again.
func (p *Playlists) tracks(ctx context.Context, playlist Playlist) ([]Track, error) {
	playlistID, ownerID := playlist.ID, playlist.OwnerID
	rows, err := p.pool.Query(ctx, `
		SELECT `+qualifiedTrackColumns("tracks")+`
		FROM playlist_tracks pt
		JOIN tracks ON tracks.id = pt.track_id
		WHERE pt.playlist_id = $1::uuid AND tracks.owner_id::text = $2 AND tracks.status = 'ready'
		ORDER BY pt.position
	`, playlistID, ownerID)
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

func (p *Playlists) Create(ctx context.Context, ownerID, name string) (Playlist, error) {
	return scanPlaylist(p.pool.QueryRow(ctx, `
		INSERT INTO playlists (owner_id, name)
		VALUES ($1::uuid, $2)
		RETURNING `+playlistColumns, ownerID, name))
}

func (p *Playlists) Rename(ctx context.Context, ownerID, playlistID, name string) (Playlist, error) {
	playlist, err := scanPlaylist(p.pool.QueryRow(ctx, `
		UPDATE playlists SET name = $3, updated_at = now()
		WHERE id::text = $1 AND owner_id::text = $2
		RETURNING `+playlistColumns, playlistID, ownerID, name))
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

// Share makes the playlist shared with the given token, or keeps the token
// it already has, so sharing twice gives the same link.
func (p *Playlists) Share(ctx context.Context, ownerID, playlistID, token string) (Playlist, error) {
	playlist, err := scanPlaylist(p.pool.QueryRow(ctx, `
		UPDATE playlists SET share_token = COALESCE(share_token, $3)
		WHERE id::text = $1 AND owner_id::text = $2
		RETURNING `+playlistColumns, playlistID, ownerID, token))
	var pgErr *pgconn.PgError
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		return Playlist{}, ErrNotFound
	case errors.As(err, &pgErr) && pgErr.Code == uniqueViolation:
		return Playlist{}, ErrShareTokenTaken
	}
	return playlist, err
}

// Unshare makes the playlist private; its link stops working for good.
func (p *Playlists) Unshare(ctx context.Context, ownerID, playlistID string) error {
	tag, err := p.pool.Exec(ctx, `
		UPDATE playlists SET share_token = NULL
		WHERE id::text = $1 AND owner_id::text = $2
	`, playlistID, ownerID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// SharedPlaylist is a playlist as someone with its link sees it.
type SharedPlaylist struct {
	Playlist
	OwnerEmail string
}

// ForShareToken returns the shared playlist and its tracks, or ErrNotFound
// when no playlist is shared with that token (never shared, or unshared).
func (p *Playlists) ForShareToken(ctx context.Context, token string) (SharedPlaylist, error) {
	var shared SharedPlaylist
	err := p.pool.QueryRow(ctx, `
		SELECT `+qualifiedPlaylistColumns+`, users.email
		FROM playlists JOIN users ON users.id = playlists.owner_id
		WHERE playlists.share_token = $1
	`, token).Scan(&shared.ID, &shared.OwnerID, &shared.Name, &shared.ShareToken,
		&shared.CreatedAt, &shared.UpdatedAt, &shared.OwnerEmail)
	if errors.Is(err, pgx.ErrNoRows) {
		return SharedPlaylist{}, ErrNotFound
	}
	if err != nil {
		return SharedPlaylist{}, err
	}
	shared.Tracks, err = p.tracks(ctx, shared.Playlist)
	return shared, err
}

// SharedTrack returns a ready track that is in the playlist shared with the
// token, or ErrNotFound. It is what lets someone with the link play it.
func (p *Playlists) SharedTrack(ctx context.Context, token, trackID string) (Track, error) {
	track, err := scanTrack(p.pool.QueryRow(ctx, `
		SELECT `+qualifiedTrackColumns("tracks")+`
		FROM playlists
		JOIN playlist_tracks pt ON pt.playlist_id = playlists.id
		JOIN tracks ON tracks.id = pt.track_id
		WHERE playlists.share_token = $1 AND tracks.id::text = $2
		  AND tracks.owner_id = playlists.owner_id AND tracks.status = 'ready'
	`, token, trackID))
	if errors.Is(err, pgx.ErrNoRows) {
		return Track{}, ErrNotFound
	}
	return track, err
}
