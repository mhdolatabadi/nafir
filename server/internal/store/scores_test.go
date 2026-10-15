package store

import (
	"strings"
	"testing"
)

func TestPopularAndTrendingScores(t *testing.T) {
	f := newCatalogFixture(t)
	likes := NewTrackLikes(f.catalog.pool)
	alice, bob, carol := f.user("alice@example.com"), f.user("bob@example.com"), f.user("carol@example.com")
	var ids []string
	for _, title := range []string{"classic", "fresh", "quiet", "hidden"} {
		ids = append(ids, f.track(alice.ID, NewTrack{Title: title}).ID)
	}
	f.playlist(alice.ID, true, ids...)
	f.indexAll()
	entry := map[string]string{}
	for _, e := range f.listed(StoreQuery{}) {
		entry[e.Track.Title] = e.ID
	}

	// classic: three plays and a like, all a month ago. fresh: two plays
	// today. quiet: nothing. hidden: much loved, then hidden.
	for _, listener := range []string{"u:" + bob.ID, "u:" + carol.ID, "a:x"} {
		if err := f.catalog.RecordStorePlay(f.ctx, entry["classic"], listener); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := likes.SetStoreLike(f.ctx, bob.ID, entry["classic"], true); err != nil {
		t.Fatal(err)
	}
	_, _ = f.catalog.pool.Exec(f.ctx, `UPDATE store_plays SET played_at = now() - interval '30 days', day = current_date - 30 WHERE entry_id::text = $1`, entry["classic"])
	_, _ = f.catalog.pool.Exec(f.ctx, `UPDATE track_likes SET created_at = now() - interval '30 days'`)
	for range 3 {
		// The same listener on the same day counts once.
		_ = f.catalog.RecordStorePlay(f.ctx, entry["fresh"], "u:"+bob.ID)
	}
	_ = f.catalog.RecordStorePlay(f.ctx, entry["fresh"], "a:y")
	for _, listener := range []string{"a:1", "a:2", "a:3", "a:4", "a:5"} {
		_ = f.catalog.RecordStorePlay(f.ctx, entry["hidden"], listener)
	}
	if err := f.catalog.SetHidden(f.ctx, entry["hidden"], alice.ID, true); err != nil {
		t.Fatal(err)
	}
	if err := f.catalog.RecordStorePlay(f.ctx, "00000000-0000-0000-0000-000000000000", "a:z"); err != nil {
		t.Fatalf("a play of an unknown song = %v", err)
	}

	if err := f.catalog.RefreshScores(f.ctx); err != nil {
		t.Fatal(err)
	}
	ranked := func(ranking StoreRanking) string {
		t.Helper()
		entries, _, err := f.catalog.StoreRanked(f.ctx, ranking, 10, 0)
		if err != nil {
			t.Fatal(err)
		}
		return titles(entries)
	}
	if got := ranked(RankPopular); got != "classic,fresh" {
		t.Fatalf("popular = %q; want all-time likes plus plays, nothing hidden or silent", got)
	}
	if got := ranked(RankTrending); got != "fresh" {
		t.Fatalf("trending = %q; want only what was liked or played lately", got)
	}
	var popular float64
	_ = f.catalog.pool.QueryRow(f.ctx, `SELECT popular FROM store_scores WHERE entry_id::text = $1`, entry["classic"]).Scan(&popular)
	if popular != 4 {
		t.Fatalf("classic popular = %v, want 3 plays + 1 like", popular)
	}

	// A fading song: recent beats a week old.
	_, _ = f.catalog.pool.Exec(f.ctx, `UPDATE store_plays SET played_at = now() - interval '7 days', day = current_date - 7 WHERE entry_id::text = $1`, entry["fresh"])
	_ = f.catalog.RecordStorePlay(f.ctx, entry["quiet"], "a:q")
	if err := f.catalog.RefreshScores(f.ctx); err != nil {
		t.Fatal(err)
	}
	if got := ranked(RankTrending); !strings.HasPrefix(got, "quiet,fresh") {
		t.Fatalf("trending = %q; one play today should beat two a week ago", got)
	}
	entries, more, _ := f.catalog.StoreRanked(f.ctx, RankPopular, 1, 0)
	if len(entries) != 1 || !more {
		t.Fatalf("first page = %d, more %v", len(entries), more)
	}
}
