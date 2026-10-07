package store

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/lyrics"
)

func TestLyricsCache(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	users := NewUsers(pool)
	tracks := NewTracks(pool)
	cache := NewLyrics(pool)
	alice, _ := users.Create(ctx, "alice@example.com", "hash")
	track, err := tracks.Create(ctx, alice.ID, NewTrack{Title: "song", FileName: "s.mp3", ContentType: "audio/mpeg", SizeBytes: 1})
	if err != nil {
		t.Fatal(err)
	}

	if _, err := cache.Lyrics(ctx, track.ID); !errors.Is(err, lyrics.ErrNotCached) {
		t.Fatalf("empty cache = %v", err)
	}
	now := time.Now().UTC().Truncate(time.Millisecond)
	found := lyrics.Entry{
		TrackID: track.ID, MatchKey: "k1", Found: true, Chosen: true,
		Record: lyrics.Record{
			ID: 42, TrackName: "Song", ArtistName: "Artist", AlbumName: "Album", Duration: 201.5,
			PlainLyrics: ptr("line"), SyncedLyrics: ptr("[00:01.00]line"),
		},
		FetchedAt: now, ExpiresAt: now.Add(time.Hour),
	}
	if err := cache.SaveLyrics(ctx, found); err != nil {
		t.Fatal(err)
	}
	got, err := cache.Lyrics(ctx, track.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Record.ID != 42 || got.Record.ArtistName != "Artist" || got.Record.Duration != 201.5 ||
		*got.Record.SyncedLyrics != "[00:01.00]line" || !got.Chosen || !got.ExpiresAt.Equal(found.ExpiresAt) {
		t.Fatalf("read back %+v", got)
	}

	// A miss replaces it and keeps nothing of the old lyrics.
	miss := lyrics.Entry{TrackID: track.ID, MatchKey: "k2", Chosen: true, FetchedAt: now, ExpiresAt: now.Add(time.Minute),
		Record: lyrics.Record{PlainLyrics: ptr("leftover")}}
	if err := cache.SaveLyrics(ctx, miss); err != nil {
		t.Fatal(err)
	}
	got, _ = cache.Lyrics(ctx, track.ID)
	if got.Found || got.Chosen || got.MatchKey != "k2" || got.Record.PlainLyrics != nil || got.Record.ID != 0 {
		t.Fatalf("miss read back %+v", got)
	}

	// Lyrics go with their track, and a lookup finishing after the track
	// was deleted saves nothing and fails nothing.
	if err := tracks.Delete(ctx, alice.ID, track.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := cache.Lyrics(ctx, track.ID); !errors.Is(err, lyrics.ErrNotCached) {
		t.Fatalf("after delete = %v", err)
	}
	if err := cache.SaveLyrics(ctx, found); err != nil {
		t.Fatalf("saving for a deleted track = %v", err)
	}
	var rows int
	_ = pool.QueryRow(ctx, "SELECT count(*) FROM track_lyrics").Scan(&rows)
	if rows != 0 {
		t.Fatalf("%d orphan rows", rows)
	}
}
