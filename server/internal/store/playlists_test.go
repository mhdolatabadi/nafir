package store

import (
	"context"
	"errors"
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

func TestSharingAPlaylist(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	owner, _ := NewUsers(pool).Create(ctx, "owner@example.com", "hash")
	other, _ := NewUsers(pool).Create(ctx, "other@example.com", "hash")
	tracks := NewTracks(pool)
	playlists := NewPlaylists(pool)

	inList, _ := tracks.Create(ctx, owner.ID, NewTrack{Title: "in", FileName: "a.mp3", ContentType: "audio/mpeg", SizeBytes: 1})
	notInList, _ := tracks.Create(ctx, owner.ID, NewTrack{Title: "out", FileName: "b.mp3", ContentType: "audio/mpeg", SizeBytes: 1})
	playlist, _ := playlists.Create(ctx, owner.ID, "mix")
	playlists.ReplaceTracks(ctx, owner.ID, playlist.ID, []string{inList.ID})

	if _, err := playlists.ForShareToken(ctx, "nothing"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("unshared lookup: %v", err)
	}
	if _, err := playlists.Share(ctx, other.ID, playlist.ID, "stolen"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("sharing someone else's playlist: %v", err)
	}
	shared, err := playlists.Share(ctx, owner.ID, playlist.ID, "token-1")
	if err != nil || shared.ShareToken == nil || *shared.ShareToken != "token-1" {
		t.Fatalf("share = %+v, %v", shared, err)
	}
	again, _ := playlists.Share(ctx, owner.ID, playlist.ID, "token-2")
	if *again.ShareToken != "token-1" {
		t.Fatalf("sharing again changed the link: %q", *again.ShareToken)
	}

	view, err := playlists.ForShareToken(ctx, "token-1")
	if err != nil || view.Name != "mix" || view.OwnerEmail != "owner@example.com" ||
		len(view.Tracks) != 1 || view.Tracks[0].ID != inList.ID {
		t.Fatalf("shared view = %+v, %v", view, err)
	}
	if got, err := playlists.SharedTrack(ctx, "token-1", inList.ID); err != nil || got.ID != inList.ID {
		t.Fatalf("track in the playlist = %+v, %v", got, err)
	}
	if _, err := playlists.SharedTrack(ctx, "token-1", notInList.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("track outside the playlist: %v", err)
	}

	other2, _ := playlists.Create(ctx, other.ID, "theirs")
	if _, err := playlists.Share(ctx, other.ID, other2.ID, "token-1"); !errors.Is(err, ErrShareTokenTaken) {
		t.Fatalf("colliding token: %v", err)
	}

	if err := playlists.Unshare(ctx, owner.ID, playlist.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := playlists.ForShareToken(ctx, "token-1"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("after unsharing: %v", err)
	}
	if _, err := playlists.SharedTrack(ctx, "token-1", inList.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("track after unsharing: %v", err)
	}
	reshared, _ := playlists.Share(ctx, owner.ID, playlist.ID, "token-3")
	if *reshared.ShareToken != "token-3" {
		t.Fatalf("resharing reused the old link: %q", *reshared.ShareToken)
	}
}

type memoryObjects struct {
	objects map[string]string
	failAt  int
	copies  int
}

func (m *memoryObjects) Copy(_ context.Context, src, dst string) error {
	m.copies++
	if m.copies == m.failAt {
		return errors.New("minio down")
	}
	m.objects[dst] = m.objects[src]
	return nil
}

func (m *memoryObjects) Remove(_ context.Context, key string) error {
	delete(m.objects, key)
	return nil
}

func TestSavingASharedPlaylistCopiesItIntoTheAccount(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	owner, _ := NewUsers(pool).Create(ctx, "owner@example.com", "hash")
	friend, _ := NewUsers(pool).Create(ctx, "friend@example.com", "hash")
	tracks := NewTracks(pool)
	playlists := NewPlaylists(pool)
	objects := &memoryObjects{objects: map[string]string{}}

	artist := "خواننده"
	a, _ := tracks.Create(ctx, owner.ID, NewTrack{Title: "a", Artist: &artist, FileName: "a.mp3", ContentType: "audio/mpeg", SizeBytes: 100})
	b, _ := tracks.Create(ctx, owner.ID, NewTrack{Title: "b", FileName: "b.flac", ContentType: "audio/flac", SizeBytes: 200})
	objects.objects[a.StorageKey], objects.objects[b.StorageKey] = "A", "B"
	playlist, _ := playlists.Create(ctx, owner.ID, "mix")
	playlists.ReplaceTracks(ctx, owner.ID, playlist.ID, []string{b.ID, a.ID})
	playlists.Share(ctx, owner.ID, playlist.ID, "tok")

	if _, err := playlists.SaveShared(ctx, owner.ID, "tok", 1000, objects); !errors.Is(err, ErrOwnPlaylist) {
		t.Fatalf("owner saving their own: %v", err)
	}
	if _, err := playlists.SaveShared(ctx, friend.ID, "tok", 250, objects); !errors.Is(err, ErrQuotaExceeded) {
		t.Fatalf("over quota: %v", err)
	}
	if _, err := playlists.SaveShared(ctx, friend.ID, "nope", 1000, objects); !errors.Is(err, ErrNotFound) {
		t.Fatalf("unknown link: %v", err)
	}

	objects.failAt = 2
	if _, err := playlists.SaveShared(ctx, friend.ID, "tok", 1000, objects); err == nil {
		t.Fatal("a failed copy was not reported")
	}
	if usage, _ := tracks.UsageForOwner(ctx, friend.ID); usage != 0 || len(objects.objects) != 2 {
		t.Fatalf("failed save left usage %d, objects %v", usage, objects.objects)
	}

	objects.failAt = 0
	saved, err := playlists.SaveShared(ctx, friend.ID, "tok", 1000, objects)
	if err != nil {
		t.Fatal(err)
	}
	if saved.OwnerID != friend.ID || saved.Name != "mix" || saved.ShareToken != nil || len(saved.Tracks) != 2 {
		t.Fatalf("saved = %+v", saved)
	}
	first := saved.Tracks[0]
	if first.OwnerID != friend.ID || first.Title != "b" || first.Source != "shared" || first.Status != TrackReady ||
		first.ID == b.ID || objects.objects[first.StorageKey] != "B" || saved.Tracks[1].Artist == nil {
		t.Fatalf("copied tracks = %+v", saved.Tracks)
	}
	if list, _ := tracks.ListForOwner(ctx, friend.ID); len(list) != 2 {
		t.Fatalf("friend's library has %d tracks", len(list))
	}

	// The copies are the friend's own: revoking the link or deleting the
	// originals does not touch them.
	playlists.Unshare(ctx, owner.ID, playlist.ID)
	tracks.Delete(ctx, owner.ID, a.ID)
	if again, _ := playlists.ForOwner(ctx, friend.ID, saved.ID); len(again.Tracks) != 2 {
		t.Fatalf("saved playlist changed with the original: %+v", again.Tracks)
	}
}
