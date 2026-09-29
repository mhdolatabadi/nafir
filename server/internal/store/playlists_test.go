package store

import (
	"context"
	"testing"
)

func TestPlaylistListsItsReadyTracksInOrder(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	user, _ := NewUsers(pool).Create(ctx, "playlist@example.com", "hash")
	tracks := NewTracks(pool)
	playlists := NewPlaylists(pool)

	first, _ := tracks.Create(ctx, user.ID, NewTrack{Title: "first", FileName: "a.mp3", ContentType: "audio/mpeg", SizeBytes: 1})
	second, _ := tracks.Create(ctx, user.ID, NewTrack{Title: "second", FileName: "b.mp3", ContentType: "audio/mpeg", SizeBytes: 1, Source: "bale"})
	playlist, err := playlists.Create(ctx, user.ID, "mix")
	if err != nil {
		t.Fatal(err)
	}
	if err := playlists.ReplaceTracks(ctx, user.ID, playlist.ID, []string{second.ID, first.ID}); err != nil {
		t.Fatal(err)
	}

	got, err := playlists.ForOwner(ctx, user.ID, playlist.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Tracks) != 2 || got.Tracks[0].ID != second.ID || got.Tracks[0].Source != "bale" || got.Tracks[1].ID != first.ID {
		t.Fatalf("tracks = %+v", got.Tracks)
	}
}
