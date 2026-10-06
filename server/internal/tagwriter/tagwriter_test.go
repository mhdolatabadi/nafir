package tagwriter

import (
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mhdolatabadi/nafir/server/internal/storage"
	"github.com/mhdolatabadi/nafir/server/internal/store"
	"github.com/mhdolatabadi/nafir/server/internal/tags"
)

// newTestPool gives this package its own database, so it can run alongside
// the store tests, which reset theirs.
func newTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	ctx := context.Background()
	admin, err := pgx.Connect(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	defer admin.Close(ctx)
	const name = "rhythmo_tagwriter_test"
	if _, err := admin.Exec(ctx, "DROP DATABASE IF EXISTS "+name+" WITH (FORCE)"); err != nil {
		t.Fatal(err)
	}
	if _, err := admin.Exec(ctx, "CREATE DATABASE "+name); err != nil {
		t.Fatal(err)
	}
	config, err := pgxpool.ParseConfig(url)
	if err != nil {
		t.Fatal(err)
	}
	config.ConnConfig.Database = name
	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	if err := store.Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	return pool
}

type memoryObjects struct {
	mu      sync.Mutex
	objects map[string][]byte
	putErr  error
	// beforePut runs before an upload is stored, to simulate what happens
	// elsewhere while a rewrite is in flight.
	beforePut func()
}

func (m *memoryObjects) Open(_ context.Context, key string) (io.ReadCloser, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	data, ok := m.objects[key]
	if !ok {
		return nil, storage.ErrObjectMissing
	}
	return io.NopCloser(bytes.NewReader(data)), nil
}

func (m *memoryObjects) Put(_ context.Context, key string, r io.Reader, size int64, _ string) error {
	if m.beforePut != nil {
		m.beforePut()
	}
	data, err := io.ReadAll(r)
	if err != nil {
		return err
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.putErr != nil {
		return m.putErr
	}
	if int64(len(data)) != size {
		return errors.New("size mismatch")
	}
	m.objects[key] = data
	return nil
}

func (m *memoryObjects) Size(_ context.Context, key string) (int64, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	data, ok := m.objects[key]
	if !ok {
		return 0, storage.ErrObjectMissing
	}
	return int64(len(data)), nil
}

func (m *memoryObjects) Remove(_ context.Context, key string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.objects, key)
	return nil
}

func (m *memoryObjects) get(key string) ([]byte, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	data, ok := m.objects[key]
	return data, ok
}

type harness struct {
	ctx     context.Context
	pool    *pgxpool.Pool
	tracks  *store.Tracks
	objects *memoryObjects
	writer  *Writer
	owner   string
}

func newHarness(t *testing.T, config Config) *harness {
	t.Helper()
	pool := newTestPool(t)
	ctx := context.Background()
	user, err := store.NewUsers(pool).Create(ctx, "tags@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	if config.MaxOwnerBytes == 0 {
		config.MaxOwnerBytes = 1 << 30
	}
	if config.TempDir == "" {
		config.TempDir = t.TempDir()
	}
	tracks := store.NewTracks(pool)
	objects := &memoryObjects{objects: map[string][]byte{}}
	return &harness{ctx: ctx, pool: pool, tracks: tracks, objects: objects, writer: New(tracks, objects, config), owner: user.ID}
}

// upload stores a fixture as a ready track.
func (h *harness) upload(t *testing.T, fixture, fileName, contentType string) store.Track {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("..", "tags", "testdata", fixture))
	if err != nil {
		t.Fatal(err)
	}
	track, err := h.tracks.Create(h.ctx, h.owner, store.NewTrack{
		Title: "Old", FileName: fileName, ContentType: contentType, SizeBytes: int64(len(data)),
	})
	if err != nil {
		t.Fatal(err)
	}
	h.objects.objects[track.StorageKey] = data
	return track
}

func (h *harness) edit(t *testing.T, track store.Track, title string) store.Track {
	t.Helper()
	artist := "خواننده"
	year := int32(2026)
	status := store.TagUnsupported
	if tags.Supported(track.FileName) {
		status = store.TagPending
	}
	edited, err := h.tracks.UpdateMetadata(h.ctx, h.owner, track.ID, track.MetadataVersion, store.TrackMetadata{
		FileName: track.FileName, Title: title, Artist: &artist, Year: &year, TagStatus: status,
	})
	if err != nil {
		t.Fatal(err)
	}
	return edited
}

func (h *harness) reload(t *testing.T, id string) store.Track {
	t.Helper()
	track, err := h.tracks.ForOwner(h.ctx, h.owner, id)
	if err != nil {
		t.Fatal(err)
	}
	return track
}

func (h *harness) runOnce(t *testing.T) bool {
	t.Helper()
	worked, err := h.writer.RunOnce(h.ctx)
	if err != nil {
		t.Fatal(err)
	}
	return worked
}

func (h *harness) garbage(t *testing.T) map[string]time.Time {
	t.Helper()
	rows, err := h.pool.Query(h.ctx, `SELECT key, delete_after FROM storage_garbage`)
	if err != nil {
		t.Fatal(err)
	}
	keys := map[string]time.Time{}
	for rows.Next() {
		var key string
		var at time.Time
		if err := rows.Scan(&key, &at); err != nil {
			t.Fatal(err)
		}
		keys[key] = at
	}
	return keys
}

func (h *harness) collect(t *testing.T) {
	t.Helper()
	if _, err := h.tracks.CollectGarbage(h.ctx, 100, h.objects.Remove); err != nil {
		t.Fatal(err)
	}
}

func embedded(t *testing.T, h *harness, track store.Track) tags.Metadata {
	t.Helper()
	data, ok := h.objects.get(track.StorageKey)
	if !ok {
		t.Fatalf("object %s is missing", track.StorageKey)
	}
	info, err := tags.Inspect(bytes.NewReader(data), track.FileName)
	if err != nil {
		t.Fatal(err)
	}
	return info.Metadata
}

func TestRewriteSwapsInVerifiedObject(t *testing.T) {
	for _, tc := range []struct{ fixture, name, contentType string }{
		{"v23-cover-id3v1.mp3", "آهنگ من.mp3", "audio/mpeg"},
		{"tagged.flac", "song.flac", "audio/flac"},
		{"tagged.ogg", "song.ogg", "audio/ogg"},
		{"tagged.opus", "song.opus", "audio/ogg"},
	} {
		t.Run(tc.fixture, func(t *testing.T) {
			h := newHarness(t, Config{Grace: time.Hour})
			original := h.upload(t, tc.fixture, tc.name, tc.contentType)
			before, _ := h.objects.get(original.StorageKey)
			edited := h.edit(t, original, "آهنگ تازه")

			// Until the job runs, the old object is the one served.
			if current := h.reload(t, original.ID); current.StorageKey != original.StorageKey || current.TagStatus != store.TagPending {
				t.Fatalf("before the job: %+v", current)
			}
			if !h.runOnce(t) {
				t.Fatal("no job was claimed")
			}
			done := h.reload(t, original.ID)
			if done.TagStatus != store.TagWritten || done.TagVersion == nil || *done.TagVersion != edited.MetadataVersion ||
				done.TagError != nil || done.PendingStorageKey != nil {
				t.Fatalf("after the job: %+v", done)
			}
			if done.StorageKey == original.StorageKey || !strings.HasPrefix(done.StorageKey, "users/"+h.owner+"/tracks/"+original.ID+"/v2-1/") {
				t.Fatalf("new key %q", done.StorageKey)
			}
			stored, _ := h.objects.get(done.StorageKey)
			if done.SizeBytes != int64(len(stored)) {
				t.Fatalf("recorded size %d, object has %d bytes", done.SizeBytes, len(stored))
			}
			if got := embedded(t, h, done); got != Metadata(done) || got.Title != "آهنگ تازه" || got.Artist != "خواننده" || got.Year != 2026 {
				t.Fatalf("embedded metadata %+v", got)
			}
			// The old object stays for the grace period, then goes.
			if still, ok := h.objects.get(original.StorageKey); !ok || !bytes.Equal(still, before) {
				t.Fatal("old object changed or vanished before its grace period")
			}
			due, queued := h.garbage(t)[original.StorageKey]
			if !queued || time.Until(due) < 50*time.Minute {
				t.Fatalf("old object queued=%v until %v", queued, due)
			}
			if _, err := h.pool.Exec(h.ctx, `UPDATE storage_garbage SET delete_after = now()`); err != nil {
				t.Fatal(err)
			}
			h.collect(t)
			if _, ok := h.objects.get(original.StorageKey); ok {
				t.Fatal("old object not removed after its grace period")
			}
			if _, ok := h.objects.get(done.StorageKey); !ok {
				t.Fatal("garbage collection removed the current object")
			}
			if h.runOnce(t) {
				t.Fatal("a written track was claimed again")
			}
		})
	}
}

func TestFailedUploadKeepsOldObjectAndRetries(t *testing.T) {
	h := newHarness(t, Config{MaxAttempts: 2, RetryDelay: time.Millisecond, Grace: time.Hour})
	original := h.upload(t, "v24.mp3", "song.mp3", "audio/mpeg")
	before, _ := h.objects.get(original.StorageKey)
	h.edit(t, original, "New")
	h.objects.putErr = errors.New("storage is down")

	h.runOnce(t)
	failed := h.reload(t, original.ID)
	if failed.TagStatus != store.TagPending || failed.TagError == nil || *failed.TagError != "upload_failed" ||
		failed.StorageKey != original.StorageKey || failed.PendingStorageKey != nil || failed.TagAttempts != 1 {
		t.Fatalf("after a failed upload: %+v", failed)
	}
	if still, _ := h.objects.get(original.StorageKey); !bytes.Equal(still, before) {
		t.Fatal("old object changed")
	}
	if _, queued := h.garbage(t)[RevisionKey(failed)]; !queued {
		t.Fatal("the failed upload's key is not queued for cleanup")
	}

	time.Sleep(10 * time.Millisecond)
	h.runOnce(t)
	if gaveUp := h.reload(t, original.ID); gaveUp.TagStatus != store.TagFailed || gaveUp.StorageKey != original.StorageKey {
		t.Fatalf("after the last attempt: %+v", gaveUp)
	}
	h.collect(t)
	if len(h.objects.objects) != 1 {
		t.Fatalf("objects left behind: %v", keys(h.objects.objects))
	}

	// Saving again starts over, and this time it works.
	h.objects.putErr = nil
	h.edit(t, h.reload(t, original.ID), "Again")
	h.runOnce(t)
	if done := h.reload(t, original.ID); done.TagStatus != store.TagWritten || embedded(t, h, done).Title != "Again" {
		t.Fatalf("retry after failure: %+v", done)
	}
}

func TestMalformedAudioFailsWithoutTouchingTheObject(t *testing.T) {
	h := newHarness(t, Config{})
	track, err := h.tracks.Create(h.ctx, h.owner, store.NewTrack{Title: "Bad", FileName: "bad.flac", ContentType: "audio/flac", SizeBytes: 12})
	if err != nil {
		t.Fatal(err)
	}
	h.objects.objects[track.StorageKey] = []byte("fLaC garbage")
	h.edit(t, track, "New")
	h.runOnce(t)
	failed := h.reload(t, track.ID)
	if failed.TagStatus != store.TagFailed || failed.TagError == nil || *failed.TagError != "malformed_audio" || failed.StorageKey != track.StorageKey {
		t.Fatalf("malformed file: %+v", failed)
	}
	if string(h.objects.objects[track.StorageKey]) != "fLaC garbage" {
		t.Fatal("object changed")
	}
}

func TestNewerEditDuringRewriteWins(t *testing.T) {
	h := newHarness(t, Config{Grace: time.Hour})
	original := h.upload(t, "tagged.flac", "song.flac", "audio/flac")
	first := h.edit(t, original, "First")
	var second store.Track
	h.objects.beforePut = func() {
		h.objects.beforePut = nil
		second = h.edit(t, first, "Second")
	}
	h.runOnce(t)
	stale := h.reload(t, original.ID)
	if stale.StorageKey != original.StorageKey || stale.TagStatus != store.TagPending || stale.Title != "Second" {
		t.Fatalf("a superseded rewrite was swapped in: %+v", stale)
	}
	h.runOnce(t)
	done := h.reload(t, original.ID)
	if done.TagStatus != store.TagWritten || *done.TagVersion != second.MetadataVersion || embedded(t, h, done).Title != "Second" {
		t.Fatalf("newest edit not written: %+v", done)
	}
	if _, err := h.pool.Exec(h.ctx, `UPDATE storage_garbage SET delete_after = now()`); err != nil {
		t.Fatal(err)
	}
	h.collect(t)
	if len(h.objects.objects) != 1 {
		t.Fatalf("objects left behind: %v", keys(h.objects.objects))
	}
}

func TestDeletedTrackDuringRewriteLeavesNoObject(t *testing.T) {
	h := newHarness(t, Config{})
	original := h.upload(t, "tagged.opus", "song.opus", "audio/ogg")
	h.edit(t, original, "New")
	h.objects.beforePut = func() {
		_ = h.objects.Remove(h.ctx, original.StorageKey)
		if err := h.tracks.Delete(h.ctx, h.owner, original.ID); err != nil {
			t.Error(err)
		}
	}
	h.runOnce(t)
	h.collect(t)
	if len(h.objects.objects) != 0 {
		t.Fatalf("objects left behind: %v", keys(h.objects.objects))
	}
}

func TestCrashedRewriteIsRecoveredByTheNextWorker(t *testing.T) {
	h := newHarness(t, Config{Lease: time.Hour})
	original := h.upload(t, "v24.mp3", "song.mp3", "audio/mpeg")
	h.edit(t, original, "New")

	// A worker claims the job, uploads its object and dies before the swap.
	claimed, ok, err := h.tracks.ClaimTagRewrite(h.ctx, time.Millisecond, 3)
	if err != nil || !ok {
		t.Fatalf("claim: %v %v", ok, err)
	}
	orphan := RevisionKey(claimed)
	if err := h.tracks.RecordPendingObject(h.ctx, claimed, orphan); err != nil {
		t.Fatal(err)
	}
	h.objects.objects[orphan] = []byte("half-written")
	time.Sleep(10 * time.Millisecond) // the lease runs out

	h.runOnce(t)
	done := h.reload(t, original.ID)
	if done.TagStatus != store.TagWritten || done.StorageKey == orphan || done.TagAttempts != 2 {
		t.Fatalf("recovery: %+v", done)
	}
	h.collect(t)
	if _, ok := h.objects.get(orphan); ok {
		t.Fatal("the crashed attempt's object was not cleaned up")
	}
	if _, ok := h.objects.get(done.StorageKey); !ok {
		t.Fatal("current object removed")
	}
}

func TestGarbageCollectionNeverDeletesAnObjectInUse(t *testing.T) {
	h := newHarness(t, Config{})
	track := h.upload(t, "v24.mp3", "song.mp3", "audio/mpeg")
	if err := h.tracks.QueueGarbage(h.ctx, track.StorageKey, "test", 0); err != nil {
		t.Fatal(err)
	}
	h.collect(t)
	if _, ok := h.objects.get(track.StorageKey); !ok {
		t.Fatal("collected an object a track still uses")
	}
	if len(h.garbage(t)) != 0 {
		t.Fatal("the stale queue entry was kept")
	}
}

func TestRewriteThatWouldExceedQuotaFails(t *testing.T) {
	h := newHarness(t, Config{})
	track := h.upload(t, "notag.mp3", "song.mp3", "audio/mpeg")
	h.writer.config.MaxOwnerBytes = track.SizeBytes // tags make the file larger
	h.edit(t, track, "A title that needs room")
	h.runOnce(t)
	failed := h.reload(t, track.ID)
	if failed.TagStatus != store.TagFailed || *failed.TagError != "quota_exceeded" || failed.StorageKey != track.StorageKey || failed.SizeBytes != track.SizeBytes {
		t.Fatalf("over quota: %+v", failed)
	}
	h.collect(t)
	if len(h.objects.objects) != 1 {
		t.Fatalf("objects left behind: %v", keys(h.objects.objects))
	}
}

func TestUnsupportedFormatsAreNeverQueued(t *testing.T) {
	h := newHarness(t, Config{})
	track := h.upload(t, "sample.m4a", "song.m4a", "audio/mp4")
	edited := h.edit(t, track, "New")
	if edited.TagStatus != store.TagUnsupported || h.runOnce(t) {
		t.Fatalf("m4a: %+v", edited)
	}
	if h.reload(t, track.ID).StorageKey != track.StorageKey {
		t.Fatal("object replaced")
	}
}

func keys(m map[string][]byte) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}
