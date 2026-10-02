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
	if aliceTrack.FileName != "song.mp3" {
		t.Fatalf("file name %q", aliceTrack.FileName)
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

func TestUpdateMetadataIsOwnerScopedAndReadyOnly(t *testing.T) {
	ctx := context.Background()
	pool := newTestPool(t)
	users, tracks := NewUsers(pool), NewTracks(pool)
	alice, _ := users.Create(ctx, "alice-update@example.com", "hash")
	bob, _ := users.Create(ctx, "bob-update@example.com", "hash")

	artist := "Artist"
	ready, err := tracks.Create(ctx, alice.ID, NewTrack{
		Title: "Old", Artist: &artist, FileName: "song.mp3", ContentType: "audio/mpeg", SizeBytes: 1,
	})
	if err != nil {
		t.Fatal(err)
	}
	pending, err := tracks.ReservePending(ctx, alice.ID, NewTrack{
		Title: "Pending", FileName: "pending.mp3", ContentType: "audio/mpeg", SizeBytes: 1,
	}, 100, 3)
	if err != nil {
		t.Fatal(err)
	}
	if ready.MetadataVersion != 1 {
		t.Fatalf("new track version = %d, want 1", ready.MetadataVersion)
	}
	if _, err := tracks.UpdateMetadata(ctx, bob.ID, ready.ID, 1, TrackMetadata{Title: "Stolen"}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("bob updated alice's track: %v", err)
	}
	// Even with a wrong version, someone else's track is not found rather
	// than a conflict, so its existence does not leak.
	if _, err := tracks.UpdateMetadata(ctx, bob.ID, ready.ID, 7, TrackMetadata{Title: "Stolen"}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("bob probing alice's track: %v", err)
	}
	if _, err := tracks.UpdateMetadata(ctx, alice.ID, pending.ID, 1, TrackMetadata{Title: "Hidden"}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("pending track update error = %v", err)
	}

	album := "Album"
	albumArtist := "Album Artist"
	composer := "Composer"
	genre := "Rock"
	comment := "Note"
	year := int32(2026)
	trackNumber := int32(7)
	discNumber := int32(1)
	updated, err := tracks.UpdateMetadata(ctx, alice.ID, ready.ID, 1, TrackMetadata{
		FileName: "آهنگ تازه.mp3", Title: "New", Album: &album, AlbumArtist: &albumArtist,
		Composer: &composer, Genre: &genre, Year: &year, TrackNumber: &trackNumber,
		DiscNumber: &discNumber, Comment: &comment,
	})
	if err != nil {
		t.Fatal(err)
	}
	if updated.FileName != "آهنگ تازه.mp3" || updated.Title != "New" || updated.Artist != nil || updated.MetadataVersion != 2 ||
		updated.Album == nil || *updated.Album != "Album" ||
		updated.AlbumArtist == nil || *updated.AlbumArtist != "Album Artist" ||
		updated.Composer == nil || *updated.Composer != "Composer" ||
		updated.Genre == nil || *updated.Genre != "Rock" ||
		updated.Year == nil || *updated.Year != 2026 ||
		updated.TrackNumber == nil || *updated.TrackNumber != 7 ||
		updated.DiscNumber == nil || *updated.DiscNumber != 1 ||
		updated.Comment == nil || *updated.Comment != "Note" {
		t.Fatalf("updated metadata = %+v", updated)
	}
	// The display name changes; the stored object does not move.
	if updated.StorageKey != ready.StorageKey {
		t.Fatalf("storage key changed to %q", updated.StorageKey)
	}

	// An edit based on the old version is a conflict and changes nothing.
	if _, err := tracks.UpdateMetadata(ctx, alice.ID, ready.ID, 1, TrackMetadata{FileName: "x.mp3", Title: "Stale"}); !errors.Is(err, ErrVersionConflict) {
		t.Fatalf("stale update error = %v, want conflict", err)
	}
	reloaded, err := tracks.ForOwner(ctx, alice.ID, ready.ID)
	if err != nil || reloaded.Title != "New" || reloaded.MetadataVersion != 2 {
		t.Fatalf("after stale update: %+v, %v", reloaded, err)
	}
}

func TestConcurrentMetadataEditsCannotBothWin(t *testing.T) {
	ctx := context.Background()
	pool := newTestPool(t)
	users, tracks := NewUsers(pool), NewTracks(pool)
	alice, _ := users.Create(ctx, "alice-race@example.com", "hash")
	track, err := tracks.Create(ctx, alice.ID, NewTrack{Title: "Old", FileName: "song.mp3", ContentType: "audio/mpeg", SizeBytes: 1})
	if err != nil {
		t.Fatal(err)
	}
	results := make(chan error, 2)
	for _, title := range []string{"One", "Two"} {
		go func() {
			_, err := tracks.UpdateMetadata(ctx, alice.ID, track.ID, 1, TrackMetadata{FileName: "song.mp3", Title: title})
			results <- err
		}()
	}
	var conflicts, wins int
	for range 2 {
		switch err := <-results; {
		case err == nil:
			wins++
		case errors.Is(err, ErrVersionConflict):
			conflicts++
		default:
			t.Fatal(err)
		}
	}
	if wins != 1 || conflicts != 1 {
		t.Fatalf("wins=%d conflicts=%d, want exactly one of each", wins, conflicts)
	}
}

func TestStorageKeyStaysASCIIForUnicodeFileNames(t *testing.T) {
	ctx := context.Background()
	pool := newTestPool(t)
	users, tracks := NewUsers(pool), NewTracks(pool)
	alice, _ := users.Create(ctx, "alice-unicode@example.com", "hash")
	track, err := tracks.Create(ctx, alice.ID, NewTrack{Title: "آهنگ", FileName: "آهنگ من.mp3", ContentType: "audio/mpeg", SizeBytes: 1})
	if err != nil {
		t.Fatal(err)
	}
	if track.FileName != "آهنگ من.mp3" {
		t.Fatalf("file name = %q", track.FileName)
	}
	if want := "users/" + alice.ID + "/tracks/" + track.ID + "/track.mp3"; track.StorageKey != want || StorageKey(alice.ID, track.ID, track.FileName) != want {
		t.Fatalf("storage key = %q, want %q", track.StorageKey, want)
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

// TestMetadataVersionMigrationKeepsExistingTracks rolls the version columns
// back to the pre-012 schema and migrates again, as on a deployed database.
func TestMetadataVersionMigrationKeepsExistingTracks(t *testing.T) {
	ctx := context.Background()
	pool := newTestPool(t)
	users, tracks := NewUsers(pool), NewTracks(pool)
	alice, _ := users.Create(ctx, "alice-migrate@example.com", "hash")
	artist := "Artist"
	before, err := tracks.Create(ctx, alice.ID, NewTrack{Title: "Old", Artist: &artist, FileName: "song.mp3", ContentType: "audio/mpeg", SizeBytes: 5})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `
		ALTER TABLE tracks DROP COLUMN metadata_version, DROP COLUMN metadata_updated_at;
		DELETE FROM schema_migrations WHERE version = 'migrations/012_add_track_metadata_version.sql';
	`); err != nil {
		t.Fatal(err)
	}
	if err := Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	after, err := tracks.ForOwner(ctx, alice.ID, before.ID)
	if err != nil {
		t.Fatal(err)
	}
	if after.MetadataVersion != 1 || after.Title != "Old" || after.Artist == nil || *after.Artist != "Artist" ||
		after.FileName != "song.mp3" || after.StorageKey != before.StorageKey || after.SizeBytes != 5 {
		t.Fatalf("migrated track = %+v", after)
	}
}
