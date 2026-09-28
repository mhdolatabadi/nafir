package store

import (
	"context"
	"errors"
	"sync"
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

func TestPendingTracksAndOwnerScopedWrites(t *testing.T) {
	ctx := context.Background()
	pool := newTestPool(t)
	users, tracks := NewUsers(pool), NewTracks(pool)
	alice, _ := users.Create(ctx, "alice@example.com", "hash")
	bob, _ := users.Create(ctx, "bob@example.com", "hash")

	pending, err := tracks.ReservePending(ctx, alice.ID, NewTrack{
		Title: "Song", FileName: "song.mp3", ContentType: "audio/mpeg", SizeBytes: 10,
	}, 1000, 3)
	if err != nil || pending.Status != TrackPending {
		t.Fatalf("CreatePending = %+v, %v", pending, err)
	}
	if list, _ := tracks.ListForOwner(ctx, alice.ID); len(list) != 0 {
		t.Fatalf("pending track listed: %+v", list)
	}

	if _, err := tracks.MarkReady(ctx, bob.ID, pending.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("bob completed alice's upload: %v", err)
	}
	if err := tracks.Delete(ctx, bob.ID, pending.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("bob deleted alice's track: %v", err)
	}

	ready, err := tracks.MarkReady(ctx, alice.ID, pending.ID)
	if err != nil || ready.Status != TrackReady {
		t.Fatalf("MarkReady = %+v, %v", ready, err)
	}
	if list, _ := tracks.ListForOwner(ctx, alice.ID); len(list) != 1 {
		t.Fatalf("ready track not listed: %+v", list)
	}

	if err := tracks.Delete(ctx, alice.ID, pending.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := tracks.ForOwner(ctx, alice.ID, pending.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("deleted track still readable: %v", err)
	}
}

func TestReservePendingSerializesConcurrentQuotaChecks(t *testing.T) {
	ctx := context.Background()
	pool := newTestPool(t)
	users, tracks := NewUsers(pool), NewTracks(pool)
	user, err := users.Create(ctx, "quota@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}

	start := make(chan struct{})
	results := make(chan error, 2)
	var ready sync.WaitGroup
	ready.Add(2)
	for i := 0; i < 2; i++ {
		go func() {
			ready.Done()
			<-start
			_, err := tracks.ReservePending(ctx, user.ID, NewTrack{
				Title: "Song", FileName: "song.mp3",
				ContentType: "audio/mpeg", SizeBytes: 60,
			}, 100, 3)
			results <- err
		}()
	}
	ready.Wait()
	close(start)

	var accepted, rejected int
	for i := 0; i < 2; i++ {
		switch err := <-results; {
		case err == nil:
			accepted++
		case errors.Is(err, ErrQuotaExceeded):
			rejected++
		default:
			t.Fatalf("unexpected reservation error: %v", err)
		}
	}
	if accepted != 1 || rejected != 1 {
		t.Fatalf("accepted=%d rejected=%d, want one of each", accepted, rejected)
	}
}

func TestReservePendingEnforcesPendingLimit(t *testing.T) {
	ctx := context.Background()
	pool := newTestPool(t)
	users, tracks := NewUsers(pool), NewTracks(pool)
	user, err := users.Create(ctx, "pending@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	newTrack := NewTrack{
		Title: "Song", FileName: "song.mp3",
		ContentType: "audio/mpeg", SizeBytes: 1,
	}
	if _, err := tracks.ReservePending(ctx, user.ID, newTrack, 100, 1); err != nil {
		t.Fatal(err)
	}
	if _, err := tracks.ReservePending(ctx, user.ID, newTrack, 100, 1); !errors.Is(err, ErrTooManyPending) {
		t.Fatalf("second pending reservation error = %v", err)
	}
}
