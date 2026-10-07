package fingerprint

import (
	"context"
	"errors"
	"io"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/store"
)

type fakeJobs struct {
	queue  []store.Track
	saved  map[string][]byte
	failed map[string]string
}

func (f *fakeJobs) ClaimFingerprintJobs(_ context.Context, limit, _ int, _ time.Duration) ([]store.Track, error) {
	n := min(limit, len(f.queue))
	jobs := f.queue[:n]
	f.queue = f.queue[n:]
	return jobs, nil
}

func (f *fakeJobs) SaveFingerprint(_ context.Context, id string, points []byte, _ time.Duration) error {
	f.saved[id] = points
	return nil
}

func (f *fakeJobs) FingerprintFailed(_ context.Context, id, reason string, _ time.Duration) error {
	f.failed[id] = reason
	return nil
}

type fakeObjects map[string]string

func (o fakeObjects) Open(_ context.Context, key string) (io.ReadCloser, error) {
	data, ok := o[key]
	if !ok {
		return nil, errors.New("object missing")
	}
	return io.NopCloser(strings.NewReader(data)), nil
}

// fakeCalc "fingerprints" a file as one item per byte, refusing "noise".
type fakeCalc struct{ seen []string }

func (c *fakeCalc) File(_ context.Context, path string) (Fingerprint, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Fingerprint{}, err
	}
	c.seen = append(c.seen, path)
	if string(data) == "noise" {
		return Fingerprint{}, ErrNoAudio
	}
	points := make([]uint32, len(data))
	for i, b := range data {
		points[i] = uint32(b)
	}
	return Fingerprint{Duration: time.Second, Points: points}, nil
}

func TestWorker(t *testing.T) {
	jobs := &fakeJobs{
		queue: []store.Track{
			{ID: "a", StorageKey: "users/u/tracks/a/a.mp3"},
			{ID: "b", StorageKey: "users/u/tracks/b/b.mp3"},
			{ID: "c", StorageKey: "users/u/tracks/c/c.mp3"},
		},
		saved: map[string][]byte{}, failed: map[string]string{},
	}
	objects := fakeObjects{"users/u/tracks/a/a.mp3": "ab", "users/u/tracks/b/b.mp3": "noise"}
	calc := &fakeCalc{}
	dir := t.TempDir()
	worker := NewWorker(jobs, objects, calc, WorkerConfig{TempDir: dir, Batch: 2})

	ctx, cancel := context.WithCancel(context.Background())
	worker.Notify()
	worker.Notify() // A second wake-up while one is pending is dropped.
	done := make(chan struct{})
	go func() {
		worker.Run(ctx)
		close(done)
	}()
	deadline := time.After(5 * time.Second)
	for len(jobs.saved)+len(jobs.failed) < 3 {
		select {
		case <-deadline:
			t.Fatal("the backlog was not worked through")
		case <-time.After(10 * time.Millisecond):
		}
	}
	cancel()
	<-done

	if got := Decode(jobs.saved["a"]); len(got) != 2 || got[0] != 'a' {
		t.Fatalf("a = %v", got)
	}
	if !strings.Contains(jobs.failed["b"], "no usable audio") || !strings.Contains(jobs.failed["c"], "object missing") {
		t.Fatalf("failures = %v", jobs.failed)
	}
	// The temporary copies are gone.
	entries, _ := os.ReadDir(dir)
	if len(entries) != 0 {
		t.Fatalf("left %d temporary files", len(entries))
	}
}

type fakeMatches []store.Matchable

func (m fakeMatches) EachMatchable(_ context.Context, _ string, fn func(store.Matchable) error) error {
	for _, item := range m {
		if err := fn(item); err != nil {
			return err
		}
	}
	return nil
}

func TestIdentifyPrefersTheBestAndOwnCopies(t *testing.T) {
	song := []uint32{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}
	noisy := append([]uint32(nil), song...)
	noisy[3] ^= 0x3
	other := []uint32{0xFFFFFFFF, 0, 0xFFFFFFFF, 0, 0xFFFFFFFF, 0, 0xFFFFFFFF, 0, 0xFFFFFFFF, 0, 0xFFFFFFFF, 0}
	shared := store.Matchable{Track: store.Track{ID: "shared", OwnerID: "bob"}, Points: Encode(song)}
	ownNoisy := store.Matchable{Track: store.Track{ID: "own", OwnerID: "alice"}, Points: Encode(noisy)}
	unrelated := store.Matchable{Track: store.Track{ID: "other", OwnerID: "alice"}, Points: Encode(other)}

	result, found, err := Identify(context.Background(), fakeMatches{unrelated, shared}, "alice", song[2:10])
	if err != nil || !found || result.Match.Track.ID != "shared" || result.Match.Points != nil {
		t.Fatalf("best = %+v %v %v", result, found, err)
	}
	// The listener's own copy wins over a slightly better playlist match.
	result, _, _ = Identify(context.Background(), fakeMatches{shared, ownNoisy}, "alice", song[2:10])
	if result.Match.Track.ID != "own" {
		t.Fatalf("own copy lost: %+v", result.Match.Track)
	}
	if _, found, _ := Identify(context.Background(), fakeMatches{unrelated}, "alice", song[2:10]); found {
		t.Fatal("matched unrelated audio")
	}
}
