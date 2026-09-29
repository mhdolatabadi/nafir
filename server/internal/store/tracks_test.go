package store

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"
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

func TestCleanupStalePendingRemovesOnlyExpiredReservations(t *testing.T) {
	ctx := context.Background()
	pool := newTestPool(t)
	users, tracks := NewUsers(pool), NewTracks(pool)
	user, err := users.Create(ctx, "cleanup@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	newTrack := NewTrack{
		Title: "Song", FileName: "song.mp3",
		ContentType: "audio/mpeg", SizeBytes: 1,
	}
	stale, err := tracks.ReservePending(ctx, user.ID, newTrack, 100, 3)
	if err != nil {
		t.Fatal(err)
	}
	fresh, err := tracks.ReservePending(ctx, user.ID, newTrack, 100, 3)
	if err != nil {
		t.Fatal(err)
	}
	ready, err := tracks.Create(ctx, user.ID, newTrack)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx,
		`UPDATE tracks SET created_at = now() - interval '3 hours' WHERE id = $1`, stale.ID,
	); err != nil {
		t.Fatal(err)
	}

	var keys []string
	removed, err := tracks.CleanupStalePending(
		ctx, time.Now().Add(-2*time.Hour), 100,
		func(_ context.Context, key string) error {
			keys = append(keys, key)
			return nil
		},
	)
	if err != nil || removed != 1 || len(keys) != 1 || keys[0] != stale.StorageKey {
		t.Fatalf("cleanup = removed %d, keys %v, err %v", removed, keys, err)
	}
	if _, err := tracks.ForOwner(ctx, user.ID, stale.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("stale reservation survived: %v", err)
	}
	for _, id := range []string{fresh.ID, ready.ID} {
		if _, err := tracks.ForOwner(ctx, user.ID, id); err != nil {
			t.Fatalf("active track %s was removed: %v", id, err)
		}
	}
}

func TestCleanupStalePendingRollsBackOnStorageFailure(t *testing.T) {
	ctx := context.Background()
	pool := newTestPool(t)
	users, tracks := NewUsers(pool), NewTracks(pool)
	user, _ := users.Create(ctx, "retry-cleanup@example.com", "hash")
	pending, err := tracks.ReservePending(ctx, user.ID, NewTrack{
		Title: "Song", FileName: "song.mp3",
		ContentType: "audio/mpeg", SizeBytes: 1,
	}, 100, 3)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx,
		`UPDATE tracks SET created_at = now() - interval '3 hours' WHERE id = $1`, pending.ID,
	); err != nil {
		t.Fatal(err)
	}

	removed, err := tracks.CleanupStalePending(
		ctx, time.Now().Add(-2*time.Hour), 100,
		func(context.Context, string) error { return errors.New("storage unavailable") },
	)
	if err == nil || removed != 0 {
		t.Fatalf("cleanup = removed %d, err %v", removed, err)
	}
	if _, err := tracks.ForOwner(ctx, user.ID, pending.ID); err != nil {
		t.Fatalf("failed cleanup did not roll back row: %v", err)
	}
}

func TestCleanupStalePendingSerializesCleaners(t *testing.T) {
	ctx := context.Background()
	pool := newTestPool(t)
	users, tracks := NewUsers(pool), NewTracks(pool)
	user, _ := users.Create(ctx, "concurrent-cleanup@example.com", "hash")
	pending, err := tracks.ReservePending(ctx, user.ID, NewTrack{
		Title: "Song", FileName: "song.mp3",
		ContentType: "audio/mpeg", SizeBytes: 1,
	}, 100, 3)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx,
		`UPDATE tracks SET created_at = now() - interval '3 hours' WHERE id = $1`, pending.ID,
	); err != nil {
		t.Fatal(err)
	}

	entered := make(chan struct{})
	release := make(chan struct{})
	first := make(chan error, 1)
	go func() {
		_, err := tracks.CleanupStalePending(
			ctx, time.Now().Add(-2*time.Hour), 100,
			func(context.Context, string) error {
				close(entered)
				<-release
				return nil
			},
		)
		first <- err
	}()
	<-entered

	removed, err := tracks.CleanupStalePending(
		ctx, time.Now().Add(-2*time.Hour), 100,
		func(context.Context, string) error {
			t.Fatal("second cleaner reached the object")
			return nil
		},
	)
	if err != nil || removed != 0 {
		t.Fatalf("second cleanup = removed %d, err %v", removed, err)
	}
	close(release)
	if err := <-first; err != nil {
		t.Fatal(err)
	}
}

func TestTrackSourceDefaultsToUpload(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	user, _ := NewUsers(pool).Create(ctx, "source@example.com", "hash")
	tracks := NewTracks(pool)

	uploaded, err := tracks.Create(ctx, user.ID, NewTrack{Title: "a", FileName: "a.mp3", ContentType: "audio/mpeg", SizeBytes: 1})
	if err != nil || uploaded.Source != "upload" {
		t.Fatalf("uploaded source = %q, %v", uploaded.Source, err)
	}
	imported, err := tracks.ReservePending(ctx, user.ID, NewTrack{
		Title: "b", FileName: "b.mp3", ContentType: "audio/mpeg", SizeBytes: 1, Source: "bale",
	}, 1000, 3)
	if err != nil || imported.Source != "bale" {
		t.Fatalf("imported source = %q, %v", imported.Source, err)
	}
	if ready, _ := tracks.MarkReady(ctx, user.ID, imported.ID); ready.Source != "bale" {
		t.Fatalf("source lost when ready: %q", ready.Source)
	}
}
