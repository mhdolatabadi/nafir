// Package loudness reads each track's ReplayGain from its own tags once and
// stores it, so the app can play tracks at an even loudness without the
// file ever being changed (#253).
package loudness

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"time"

	"github.com/mhdolatabadi/rhythmo/server/internal/storage"
	"github.com/mhdolatabadi/rhythmo/server/internal/store"
	"github.com/mhdolatabadi/rhythmo/server/internal/tags"
)

// Store is the queue of tracks to scan; *store.Tracks implements it.
type Store interface {
	PendingLoudness(ctx context.Context, limit int) ([]store.LoudnessJob, error)
	SetLoudness(ctx context.Context, trackID, storageKey string, l store.Loudness) error
}

// Objects opens stored files; *storage.Storage implements it.
type Objects interface {
	Open(ctx context.Context, key string) (io.ReadCloser, error)
}

// Scanner works through unscanned tracks in batches: new uploads and, the
// first time it runs, every track uploaded before it existed.
type Scanner struct {
	store    Store
	objects  Objects
	interval time.Duration
	batch    int
	timeout  time.Duration
}

func NewScanner(s Store, objects Objects, interval time.Duration, batch int) *Scanner {
	return &Scanner{store: s, objects: objects, interval: interval, batch: batch, timeout: 30 * time.Second}
}

// Run scans until ctx ends.
func (s *Scanner) Run(ctx context.Context) {
	ticker := time.NewTicker(s.interval)
	defer ticker.Stop()
	for {
		// A full batch means more are waiting: carry on without waiting.
		for {
			scanned, err := s.ScanOnce(ctx)
			if err != nil {
				slog.Warn("loudness scan failed", "error", err)
				break
			}
			if scanned < s.batch {
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

// ScanOnce scans one batch and returns how many tracks it settled. A track
// whose file can't be read for now is left for a later batch.
func (s *Scanner) ScanOnce(ctx context.Context) (int, error) {
	jobs, err := s.store.PendingLoudness(ctx, s.batch)
	if err != nil {
		return 0, err
	}
	settled := 0
	for _, job := range jobs {
		if ctx.Err() != nil {
			return settled, ctx.Err()
		}
		found, err := s.read(ctx, job)
		if err != nil {
			slog.Warn("loudness: track left for later", "track", job.ID, "error", err)
			continue
		}
		err = s.store.SetLoudness(ctx, job.ID, job.StorageKey, found)
		if err != nil && !errors.Is(err, store.ErrNotFound) {
			return settled, err
		}
		settled++
	}
	return settled, nil
}

// read returns the file's ReplayGain. Formats without such tags, malformed
// files and objects that are gone count as "no ReplayGain", so they are not
// tried again and again.
func (s *Scanner) read(ctx context.Context, job store.LoudnessJob) (store.Loudness, error) {
	ctx, cancel := context.WithTimeout(ctx, s.timeout)
	defer cancel()
	body, err := s.objects.Open(ctx, job.StorageKey)
	if errors.Is(err, storage.ErrObjectMissing) {
		return store.Loudness{}, nil
	}
	if err != nil {
		return store.Loudness{}, err
	}
	defer body.Close()
	found, err := tags.ReadLoudness(body, job.FileName)
	switch {
	case errors.Is(err, tags.ErrUnsupported), errors.Is(err, tags.ErrMalformed):
		return store.Loudness{}, nil
	case err != nil:
		return store.Loudness{}, err
	}
	return store.Loudness{
		TrackGainDB: found.TrackGainDB, TrackPeak: found.TrackPeak,
		AlbumGainDB: found.AlbumGainDB, AlbumPeak: found.AlbumPeak,
	}, nil
}
