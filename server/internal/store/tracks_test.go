package store

import (
	"context"
	"errors"
	"testing"
)

func TestTracksAreScopedToTheirOwner(t *testing.T) {
	ctx := context.Background()
	pool := newTestPool(t)
	users, tracks := NewUsers(pool), NewTracks(pool)
	alice, _ := users.Create(ctx, "alice@example.com", "hash")
	bob, _ := users.Create(ctx, "bob@example.com", "hash")

	artist := "Artist"
	aliceTrack, err := tracks.Create(ctx, alice.ID, NewTrack{
		Title: "Song", Artist: &artist, FileName: "song.mp3", ContentType: "audio/mpeg", SizeBytes: 1234,
	})
	if err != nil {
		t.Fatal(err)
	}
	if want := StorageKey(alice.ID, aliceTrack.ID, "song.mp3"); aliceTrack.StorageKey != want {
		t.Fatalf("storage key %q, want %q", aliceTrack.StorageKey, want)
	}
	if _, err := tracks.Create(ctx, bob.ID, NewTrack{
		Title: "Other", FileName: "other.mp3", ContentType: "audio/mpeg", SizeBytes: 1,
	}); err != nil {
		t.Fatal(err)
	}

	aliceList, err := tracks.ListForOwner(ctx, alice.ID)
	if err != nil || len(aliceList) != 1 || aliceList[0].ID != aliceTrack.ID || *aliceList[0].Artist != "Artist" {
		t.Fatalf("alice list = %+v, %v", aliceList, err)
	}
	if got, err := tracks.ForOwner(ctx, alice.ID, aliceTrack.ID); err != nil || got.ID != aliceTrack.ID {
		t.Fatalf("ForOwner(alice) = %+v, %v", got, err)
	}
	if _, err := tracks.ForOwner(ctx, bob.ID, aliceTrack.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("bob read alice's track: %v", err)
	}
	if _, err := tracks.ForOwner(ctx, alice.ID, "not-a-uuid"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("malformed id: expected ErrNotFound, got %v", err)
	}

	if _, err := pool.Exec(ctx, "DELETE FROM users WHERE id = $1", alice.ID); err != nil {
		t.Fatal(err)
	}
	if list, _ := tracks.ListForOwner(ctx, alice.ID); len(list) != 0 {
		t.Fatalf("tracks survived their owner: %+v", list)
	}
}
