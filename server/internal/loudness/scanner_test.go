package loudness

import (
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"testing"

	"github.com/mhdolatabadi/rhythmo/server/internal/storage"
	"github.com/mhdolatabadi/rhythmo/server/internal/store"
)

type fakeStore struct {
	jobs []store.LoudnessJob
	set  map[string]store.Loudness
	gone map[string]bool // tracks whose object changed before SetLoudness
}

func (f *fakeStore) PendingLoudness(_ context.Context, limit int) ([]store.LoudnessJob, error) {
	var out []store.LoudnessJob
	for _, job := range f.jobs {
		if _, done := f.set[job.ID]; !done && len(out) < limit {
			out = append(out, job)
		}
	}
	return out, nil
}

func (f *fakeStore) SetLoudness(_ context.Context, id, _ string, l store.Loudness) error {
	if f.gone[id] {
		return store.ErrNotFound
	}
	f.set[id] = l
	return nil
}

type fakeObjects map[string][]byte

func (f fakeObjects) Open(_ context.Context, key string) (io.ReadCloser, error) {
	data, ok := f[key]
	if key == "flaky" {
		return nil, errors.New("connection reset")
	}
	if !ok {
		return nil, storage.ErrObjectMissing
	}
	return io.NopCloser(bytes.NewReader(data)), nil
}

func fixture(t *testing.T, name string) []byte {
	t.Helper()
	data, err := os.ReadFile("../tags/testdata/" + name)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func TestScanOnceStoresWhatTheTagsSay(t *testing.T) {
	objects := fakeObjects{
		"k/rg.mp3":    fixture(t, "replaygain.mp3"),
		"k/plain.mp3": fixture(t, "notag.mp3"),
		"k/song.m4a":  fixture(t, "sample.m4a"),
		"k/bad.flac":  []byte("not a flac"),
	}
	s := &fakeStore{set: map[string]store.Loudness{}, jobs: []store.LoudnessJob{
		{ID: "rg", StorageKey: "k/rg.mp3", FileName: "rg.mp3"},
		{ID: "plain", StorageKey: "k/plain.mp3", FileName: "plain.mp3"},
		{ID: "m4a", StorageKey: "k/song.m4a", FileName: "song.m4a"},
		{ID: "bad", StorageKey: "k/bad.flac", FileName: "bad.flac"},
		{ID: "missing", StorageKey: "k/none.mp3", FileName: "none.mp3"},
		{ID: "flaky", StorageKey: "flaky", FileName: "f.mp3"},
	}}
	scanner := NewScanner(s, objects, 0, 10)

	settled, err := scanner.ScanOnce(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if settled != 5 {
		t.Fatalf("settled %d, want 5 (all but the flaky one)", settled)
	}
	rg := s.set["rg"]
	if rg.TrackGainDB == nil || *rg.TrackGainDB != -7.25 || rg.AlbumPeak == nil || *rg.AlbumPeak != 1.012 {
		t.Fatalf("rg = %+v", rg)
	}
	for _, id := range []string{"plain", "m4a", "bad", "missing"} {
		if l, ok := s.set[id]; !ok || l.TrackGainDB != nil {
			t.Errorf("%s = %+v, %v; want scanned without ReplayGain", id, l, ok)
		}
	}
	if _, ok := s.set["flaky"]; ok {
		t.Error("a storage error must leave the track for a later scan")
	}
}

func TestScanOnceSkipsTracksWhoseFileChanged(t *testing.T) {
	s := &fakeStore{set: map[string]store.Loudness{}, gone: map[string]bool{"t1": true},
		jobs: []store.LoudnessJob{{ID: "t1", StorageKey: "k", FileName: "a.mp3"}}}
	settled, err := NewScanner(s, fakeObjects{"k": fixture(t, "replaygain.mp3")}, 0, 10).ScanOnce(context.Background())
	if err != nil || settled != 1 {
		t.Fatalf("settled %d, %v", settled, err)
	}
}
