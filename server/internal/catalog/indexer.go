// Package catalog keeps the public store's catalog (#243): every song in a
// public playlist is grouped with its other copies into one store entry,
// by acoustic fingerprint, else by normalized title and artist with a close
// duration. What the store lists is decided live by the store package; the
// indexer only maintains the grouping, so its lag never exposes anything.
package catalog

import (
	"context"
	"log/slog"
	"strings"
	"time"
	"unicode"

	"github.com/mhdolatabadi/nafir/server/internal/fingerprint"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

// Store keeps the grouping; *store.Catalog implements it.
type Store interface {
	PendingCatalogTracks(ctx context.Context, limit int, settle time.Duration) ([]store.CatalogJob, error)
	CatalogCandidates(ctx context.Context, titleKey string, durationSeconds *float64, window float64) ([]store.CatalogCandidate, error)
	AddToEntry(ctx context.Context, trackID, entryID string, points []byte, durationSeconds *float64) error
	NewEntry(ctx context.Context, trackID, titleKey string, points []byte, durationSeconds *float64) error
	PruneCatalog(ctx context.Context) (int64, error)
}

const (
	// DuplicateConfidence is the least fingerprint score at which two
	// copies are the same recording. Re-encodes of one recording score far
	// above it; different recordings, even of the same song, far below.
	DuplicateConfidence = 0.55
	// DurationWindow is how far apart, in seconds, two copies of one
	// recording may be: encoders pad or trim a little.
	DurationWindow = 3.0
	// compareWindow is how much of a new copy, from its middle, is compared.
	compareWindow = 30 * time.Second
)

// Config tunes the indexer; zero values pick defaults.
type Config struct {
	// Interval is how often a pass runs.
	Interval time.Duration
	// Batch is how many copies one pass groups.
	Batch int
	// Settle is how long a copy waits for its fingerprint before it is
	// grouped by name alone.
	Settle time.Duration
}

// Indexer groups new copies and prunes copies that left the store.
type Indexer struct {
	store  Store
	config Config
}

func NewIndexer(s Store, config Config) *Indexer {
	if config.Interval <= 0 {
		config.Interval = 30 * time.Second
	}
	if config.Batch <= 0 {
		config.Batch = 50
	}
	if config.Settle <= 0 {
		config.Settle = 10 * time.Minute
	}
	return &Indexer{store: s, config: config}
}

// Run indexes until ctx ends.
func (x *Indexer) Run(ctx context.Context) {
	ticker := time.NewTicker(x.config.Interval)
	defer ticker.Stop()
	for {
		for {
			done, err := x.RunOnce(ctx)
			if err != nil && ctx.Err() == nil {
				slog.Error("store catalog pass failed", "error", err)
			}
			if err != nil || done < x.config.Batch {
				break
			}
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

// RunOnce prunes, then groups one batch, and reports how many copies it
// grouped.
func (x *Indexer) RunOnce(ctx context.Context) (int, error) {
	if _, err := x.store.PruneCatalog(ctx); err != nil {
		return 0, err
	}
	jobs, err := x.store.PendingCatalogTracks(ctx, x.config.Batch, x.config.Settle)
	if err != nil {
		return 0, err
	}
	for _, job := range jobs {
		if err := x.group(ctx, job); err != nil {
			return 0, err
		}
	}
	return len(jobs), nil
}

func (x *Indexer) group(ctx context.Context, job store.CatalogJob) error {
	key := TitleKey(job.Track)
	duration := job.DurationSeconds
	if duration == nil && job.Track.DurationMS != nil && *job.Track.DurationMS > 0 {
		seconds := float64(*job.Track.DurationMS) / 1000
		duration = &seconds
	}
	candidates, err := x.store.CatalogCandidates(ctx, key, duration, DurationWindow)
	if err != nil {
		return err
	}
	if entryID, ok := Duplicate(key, job.Points, duration, candidates); ok {
		return x.store.AddToEntry(ctx, job.Track.ID, entryID, job.Points, duration)
	}
	return x.store.NewEntry(ctx, job.Track.ID, key, job.Points, duration)
}

// Duplicate picks the entry a copy belongs to, if any. With fingerprints on
// both sides, sound decides: the best score at or above
// DuplicateConfidence wins, and copies that don't sound alike are never
// merged by name. Otherwise the same title key and a duration within
// DurationWindow (or unknown) is a duplicate.
func Duplicate(key string, points []byte, duration *float64, candidates []store.CatalogCandidate) (string, bool) {
	var snippet []uint32
	if len(points) > 0 {
		snippet = middle(fingerprint.Decode(points))
	}
	bestID, best := "", 0.0
	for _, c := range candidates {
		if len(snippet) == 0 || len(c.Points) == 0 || !closeDurations(duration, c.DurationSeconds) {
			continue
		}
		if score := fingerprint.Compare(snippet, fingerprint.Decode(c.Points)); score.Confidence >= DuplicateConfidence && score.Confidence > best {
			bestID, best = c.EntryID, score.Confidence
		}
	}
	if bestID != "" {
		return bestID, true
	}
	for _, c := range candidates {
		if c.TitleKey != key || !closeDurations(duration, c.DurationSeconds) {
			continue
		}
		if len(snippet) > 0 && len(c.Points) > 0 {
			// Both fingerprinted and they didn't match: a different
			// recording that shares the name, such as a live version.
			continue
		}
		return c.EntryID, true
	}
	return "", false
}

func closeDurations(a, b *float64) bool {
	if a == nil || b == nil {
		return true
	}
	d := *a - *b
	return d <= DurationWindow && d >= -DurationWindow
}

// middle is up to compareWindow of points around the middle, which is
// least affected by the silence and fades encoders handle differently.
func middle(points []uint32) []uint32 {
	n := int(compareWindow / fingerprint.ItemDuration)
	if len(points) <= n {
		return points
	}
	start := (len(points) - n) / 2
	return points[start : start+n]
}

// TitleKey is the name two copies of one song share, however their
// metadata was typed: title and artist (or album artist), folded as store
// search folds them, with punctuation and spacing dropped. A track
// without a usable title gets a key of its own, so unnamed tracks are
// never grouped by name.
func TitleKey(track store.Track) string {
	title := keyPart(track.Title)
	if title == "" {
		return "track:" + track.ID
	}
	artist := ""
	if track.Artist != nil {
		artist = keyPart(*track.Artist)
	}
	if artist == "" && track.AlbumArtist != nil {
		artist = keyPart(*track.AlbumArtist)
	}
	return title + "|" + artist
}

func keyPart(s string) string {
	words := strings.FieldsFunc(Fold(s), func(r rune) bool { return !unicode.IsLetter(r) && !unicode.IsDigit(r) })
	return strings.Join(words, " ")
}

// foldReplacer mirrors the store_fold SQL function (migration 043).
var foldReplacer = strings.NewReplacer(
	"ي", "ی", "ى", "ی", "ئ", "ی", "ك", "ک",
	"ة", "ه", "ۀ", "ه", "أ", "ا", "إ", "ا",
	"آ", "ا", "ؤ", "و", "‌", " ",
	"ً", "", "ٌ", "", "ٍ", "", "َ", "", "ُ", "",
	"ِ", "", "ّ", "", "ْ", "", "ٰ", "", "ـ", "",
)

// Fold lower-cases s and folds Persian and Arabic letter variants, as
// store search does.
func Fold(s string) string {
	return foldReplacer.Replace(strings.ToLower(s))
}
