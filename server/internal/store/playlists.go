package store

import (
	"context"
	"errors"
	"fmt"
	"path"
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
	// IsPublic lists a shared playlist for everyone to discover; otherwise
	// only people with its link find it.
	IsPublic  bool
	CreatedAt time.Time
	UpdatedAt time.Time
	Tracks    []Track
}

// ErrShareTokenTaken means a newly drawn share token collided; draw again.
var ErrShareTokenTaken = errors.New("share token is already in use")

// playlistColumnNames is the one list of columns scanPlaylist reads, in order.
var playlistColumnNames = []string{"id::text", "owner_id::text", "name", "share_token", "is_public", "created_at", "updated_at"}

var (
	playlistColumns          = strings.Join(playlistColumnNames, ", ")
	qualifiedPlaylistColumns = qualifyColumns("playlists", playlistColumnNames)
)

func scanPlaylist(row pgx.Row) (Playlist, error) {
	var p Playlist
	err := row.Scan(&p.ID, &p.OwnerID, &p.Name, &p.ShareToken, &p.IsPublic, &p.CreatedAt, &p.UpdatedAt)
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
// it already has, so sharing twice gives the same link. A non-nil public
// sets whether it is listed for everyone; nil keeps what it was.
func (p *Playlists) Share(ctx context.Context, ownerID, playlistID, token string, public *bool) (Playlist, error) {
	playlist, err := scanPlaylist(p.pool.QueryRow(ctx, `
		UPDATE playlists SET share_token = COALESCE(share_token, $3), is_public = COALESCE($4, is_public)
		WHERE id::text = $1 AND owner_id::text = $2
		RETURNING `+playlistColumns, playlistID, ownerID, token, public))
	var pgErr *pgconn.PgError
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		return Playlist{}, ErrNotFound
	case errors.As(err, &pgErr) && pgErr.Code == uniqueViolation:
		return Playlist{}, ErrShareTokenTaken
	}
	return playlist, err
}

// Unshare makes the playlist private; its link stops working for good and
// it is no longer listed. Its likes are kept for if it is shared again.
func (p *Playlists) Unshare(ctx context.Context, ownerID, playlistID string) error {
	tag, err := p.pool.Exec(ctx, `
		UPDATE playlists SET share_token = NULL, is_public = false
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
		&shared.IsPublic, &shared.CreatedAt, &shared.UpdatedAt, &shared.OwnerEmail)
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

// ErrOwnPlaylist means someone tried to save their own shared playlist.
var ErrOwnPlaylist = errors.New("the playlist is already yours")

// ObjectCopier copies and removes stored audio.
type ObjectCopier interface {
	Copy(ctx context.Context, srcKey, dstKey string) error
	Remove(ctx context.Context, key string) error
}

// SaveShared copies the playlist shared with token into the user's account:
// each of its tracks becomes the user's own track (its audio copied in
// storage), collected in a new playlist with the same name. The copies
// count against the user's quota; if they don't fit, nothing is copied.
// A failure part way removes what was copied so far.
func (p *Playlists) SaveShared(
	ctx context.Context, userID, token string, maxOwnerBytes int64, objects ObjectCopier,
) (Playlist, error) {
	shared, err := p.ForShareToken(ctx, token)
	if err != nil {
		return Playlist{}, err
	}
	if shared.OwnerID == userID {
		return Playlist{}, ErrOwnPlaylist
	}

	// Reserve every copy as pending under the quota, atomically.
	var copies []Track
	err = pgx.BeginFunc(ctx, p.pool, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, userID); err != nil {
			return err
		}
		var used, needed int64
		if err := tx.QueryRow(ctx, `
			SELECT COALESCE(SUM(size_bytes), 0)::bigint FROM tracks WHERE owner_id::text = $1
		`, userID).Scan(&used); err != nil {
			return err
		}
		for _, t := range shared.Tracks {
			needed += t.SizeBytes
		}
		if used > maxOwnerBytes || needed > maxOwnerBytes-used {
			return ErrQuotaExceeded
		}
		for _, t := range shared.Tracks {
			copied, err := createTrack(ctx, tx, userID, NewTrack{
				Title: t.Title, Artist: t.Artist, Album: t.Album, DurationMS: t.DurationMS,
				FileName: path.Base(t.StorageKey), ContentType: t.ContentType, SizeBytes: t.SizeBytes,
				Source: "shared",
			}, TrackPending)
			if err != nil {
				return err
			}
			copies = append(copies, copied)
		}
		return nil
	})
	if err != nil {
		return Playlist{}, err
	}

	discard := func(done int) {
		cleanup := context.WithoutCancel(ctx)
		for _, c := range copies[:done] {
			_ = objects.Remove(cleanup, c.StorageKey)
		}
		for _, c := range copies {
			_, _ = p.pool.Exec(cleanup, `DELETE FROM tracks WHERE id::text = $1 AND status = 'pending'`, c.ID)
		}
	}
	for i, c := range copies {
		if err := objects.Copy(ctx, shared.Tracks[i].StorageKey, c.StorageKey); err != nil {
			discard(i)
			return Playlist{}, fmt.Errorf("copy track audio: %w", err)
		}
	}

	var saved Playlist
	err = pgx.BeginFunc(ctx, p.pool, func(tx pgx.Tx) error {
		var err error
		saved, err = scanPlaylist(tx.QueryRow(ctx, `
			INSERT INTO playlists (owner_id, name) VALUES ($1::uuid, $2)
			RETURNING `+playlistColumns, userID, shared.Name))
		if err != nil {
			return err
		}
		for i, c := range copies {
			if _, err := tx.Exec(ctx, `UPDATE tracks SET status = 'ready' WHERE id::text = $1`, c.ID); err != nil {
				return err
			}
			if _, err := tx.Exec(ctx, `
				INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES ($1::uuid, $2::uuid, $3)
			`, saved.ID, c.ID, i); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		discard(len(copies))
		return Playlist{}, err
	}
	saved.Tracks, err = p.tracks(ctx, saved)
	return saved, err
}

// Likes is a shared playlist's like count and whether one user likes it.
type Likes struct {
	Count int
	Liked bool
}

// LikesFor returns the playlist's likes as userID sees them.
func (p *Playlists) LikesFor(ctx context.Context, playlistID, userID string) (Likes, error) {
	var likes Likes
	err := p.pool.QueryRow(ctx, `
		SELECT count(*)::int, COALESCE(bool_or(user_id::text = $2), false)
		FROM playlist_likes WHERE playlist_id = $1::uuid
	`, playlistID, userID).Scan(&likes.Count, &likes.Liked)
	return likes, err
}

// SetLike likes or unlikes the playlist shared with token for the user and
// returns its likes after. Doing it twice is the same as once. It is
// ErrNotFound when no playlist is shared with the token.
func (p *Playlists) SetLike(ctx context.Context, userID, token string, liked bool) (Likes, error) {
	var likes Likes
	err := pgx.BeginFunc(ctx, p.pool, func(tx pgx.Tx) error {
		// Holding the row keeps it shared until the like is in.
		var playlistID string
		err := tx.QueryRow(ctx, `
			SELECT id::text FROM playlists WHERE share_token = $1 FOR SHARE
		`, token).Scan(&playlistID)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if liked {
			_, err = tx.Exec(ctx, `
				INSERT INTO playlist_likes (playlist_id, user_id) VALUES ($1::uuid, $2::uuid)
				ON CONFLICT DO NOTHING
			`, playlistID, userID)
		} else {
			_, err = tx.Exec(ctx, `
				DELETE FROM playlist_likes WHERE playlist_id = $1::uuid AND user_id::text = $2
			`, playlistID, userID)
		}
		if err != nil {
			return err
		}
		return tx.QueryRow(ctx, `
			SELECT count(*)::int FROM playlist_likes WHERE playlist_id = $1::uuid
		`, playlistID).Scan(&likes.Count)
	})
	likes.Liked = liked
	return likes, err
}

// PublicPlaylist is a public playlist as it is listed for discovery.
type PublicPlaylist struct {
	ShareToken string
	Name       string
	OwnerID    string
	OwnerEmail string
	TrackCount int
	Likes      Likes
	UpdatedAt  time.Time
}

// Popular lists up to limit public shared playlists, most liked first;
// ties go to the most recently updated, then by id, so the order is stable.
// Link-only playlists are never listed.
func (p *Playlists) Popular(ctx context.Context, userID string, limit int) ([]PublicPlaylist, error) {
	rows, err := p.pool.Query(ctx, `
		SELECT playlists.share_token, playlists.name, playlists.owner_id::text, users.email,
			(SELECT count(*)::int FROM playlist_tracks pt JOIN tracks ON tracks.id = pt.track_id
			 WHERE pt.playlist_id = playlists.id AND tracks.owner_id = playlists.owner_id
			   AND tracks.status = 'ready'),
			likes.count, likes.liked, playlists.updated_at
		FROM playlists
		JOIN users ON users.id = playlists.owner_id
		CROSS JOIN LATERAL (
			SELECT count(*)::int AS count, COALESCE(bool_or(user_id::text = $1), false) AS liked
			FROM playlist_likes WHERE playlist_id = playlists.id
		) likes
		WHERE playlists.is_public AND playlists.share_token IS NOT NULL
		ORDER BY likes.count DESC, playlists.updated_at DESC, playlists.id
		LIMIT $2
	`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	listed := []PublicPlaylist{}
	for rows.Next() {
		var pp PublicPlaylist
		if err := rows.Scan(&pp.ShareToken, &pp.Name, &pp.OwnerID, &pp.OwnerEmail, &pp.TrackCount,
			&pp.Likes.Count, &pp.Likes.Liked, &pp.UpdatedAt); err != nil {
			return nil, err
		}
		listed = append(listed, pp)
	}
	return listed, rows.Err()
}
