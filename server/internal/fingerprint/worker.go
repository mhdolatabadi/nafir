package fingerprint

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"os"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/store"
)

// JobStore hands out tracks to fingerprint and keeps the results;
// *store.Fingerprints implements it.
type JobStore interface {
	ClaimFingerprintJobs(ctx context.Context, limit, maxAttempts int, lease time.Duration) ([]store.Track, error)
	SaveFingerprint(ctx context.Context, trackID string, points []byte, duration time.Duration) error
	FingerprintFailed(ctx context.Context, trackID, reason string, retryAfter time.Duration) error
}

// Objects reads stored audio; *storage.Storage implements it.
type Objects interface {
	Open(ctx context.Context, key string) (io.ReadCloser, error)
}

// Fingerprinter computes a file's fingerprint; Calculator implements it.
type Fingerprinter interface {
	File(ctx context.Context, path string) (Fingerprint, error)
}

// WorkerConfig tunes the worker; zero values pick defaults.
type WorkerConfig struct {
	// TempDir holds the temporary copy of a track while it is read.
	TempDir string
	// Interval is how often the worker looks for tracks without a
	// fingerprint when nothing wakes it.
	Interval time.Duration
	// Batch is how many tracks one pass claims.
	Batch int
	// MaxAttempts is how often a track is tried before giving up.
	MaxAttempts int
}

// Worker fingerprints ready tracks in the background: right after an
// upload completes (Notify), after imports and copies on its next pass,
// and every older track until the backfill is done.
type Worker struct {
	jobs    JobStore
	objects Objects
	calc    Fingerprinter
	config  WorkerConfig
	wake    chan struct{}
}

func NewWorker(jobs JobStore, objects Objects, calc Fingerprinter, config WorkerConfig) *Worker {
	if config.Interval <= 0 {
		config.Interval = time.Minute
	}
	if config.Batch <= 0 {
		config.Batch = 4
	}
	if config.MaxAttempts <= 0 {
		config.MaxAttempts = 3
	}
	return &Worker{jobs: jobs, objects: objects, calc: calc, config: config, wake: make(chan struct{}, 1)}
}

// Notify starts a pass soon, for example after an upload completes.
func (w *Worker) Notify() {
	select {
	case w.wake <- struct{}{}:
	default:
	}
}

// Run works until ctx ends.
func (w *Worker) Run(ctx context.Context) {
	ticker := time.NewTicker(w.config.Interval)
	defer ticker.Stop()
	for {
		// Keep going while there is a backlog, then wait.
		for {
			done, err := w.RunOnce(ctx)
			if err != nil && ctx.Err() == nil {
				slog.Error("fingerprint pass failed", "error", err)
			}
			if err != nil || done == 0 {
				break
			}
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		case <-w.wake:
		}
	}
}

// RunOnce fingerprints one batch and reports how many tracks it handled.
func (w *Worker) RunOnce(ctx context.Context) (int, error) {
	lease := 10 * time.Minute
	jobs, err := w.jobs.ClaimFingerprintJobs(ctx, w.config.Batch, w.config.MaxAttempts, lease)
	if err != nil {
		return 0, err
	}
	for _, track := range jobs {
		fp, err := w.fingerprint(ctx, track)
		if err == nil {
			err = w.jobs.SaveFingerprint(ctx, track.ID, Encode(fp.Points), fp.Duration)
			if err == nil {
				continue
			}
		}
		if ctx.Err() != nil {
			return 0, ctx.Err()
		}
		slog.Warn("track not fingerprinted", "track", track.ID, "error", err)
		retry := 15 * time.Minute
		if errors.Is(err, ErrNoAudio) {
			retry = 24 * time.Hour
		}
		if err := w.jobs.FingerprintFailed(ctx, track.ID, err.Error(), retry); err != nil {
			return 0, err
		}
	}
	return len(jobs), nil
}

// fingerprint reads the track's object into a temporary file, which is
// removed as soon as fpcalc is done. The stored object is only read.
func (w *Worker) fingerprint(ctx context.Context, track store.Track) (Fingerprint, error) {
	file, err := os.CreateTemp(w.config.TempDir, "rhythmo-fp-*")
	if err != nil {
		return Fingerprint{}, err
	}
	defer os.Remove(file.Name())
	defer file.Close()
	object, err := w.objects.Open(ctx, track.StorageKey)
	if err != nil {
		return Fingerprint{}, err
	}
	_, err = io.Copy(file, object)
	object.Close()
	if err != nil {
		return Fingerprint{}, err
	}
	if err := file.Close(); err != nil {
		return Fingerprint{}, err
	}
	return w.calc.File(ctx, file.Name())
}
