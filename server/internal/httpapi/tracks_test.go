package httpapi

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/storage"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

const testMaxUpload = 1000

type memoryTracks struct {
	mu     sync.Mutex
	nextID int
	tracks []store.Track
	// leaky ignores the owner, to prove the handler does not rely on the store alone.
	leaky bool
}

func (m *memoryTracks) ListForOwner(_ context.Context, ownerID string) ([]store.Track, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var owned []store.Track
	for _, track := range m.tracks {
		if track.OwnerID == ownerID && track.Status == store.TrackReady {
			owned = append(owned, track)
		}
	}
	return owned, nil
}

func (m *memoryTracks) ForOwner(_ context.Context, ownerID, trackID string) (store.Track, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, track := range m.tracks {
		if track.ID == trackID && (m.leaky || track.OwnerID == ownerID) {
			return track, nil
		}
	}
	return store.Track{}, store.ErrNotFound
}

func (m *memoryTracks) CreatePending(_ context.Context, ownerID string, t store.NewTrack) (store.Track, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.nextID++
	id := "t" + string(rune('0'+m.nextID))
	track := store.Track{
		ID: id, OwnerID: ownerID, Status: store.TrackPending, Title: t.Title, Artist: t.Artist,
		StorageKey: store.StorageKey(ownerID, id, t.FileName), ContentType: t.ContentType, SizeBytes: t.SizeBytes,
	}
	m.tracks = append(m.tracks, track)
	return track, nil
}

func (m *memoryTracks) MarkReady(_ context.Context, ownerID, trackID string) (store.Track, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for i, track := range m.tracks {
		if track.ID == trackID && track.OwnerID == ownerID {
			m.tracks[i].Status = store.TrackReady
			return m.tracks[i], nil
		}
	}
	return store.Track{}, store.ErrNotFound
}

func (m *memoryTracks) Delete(_ context.Context, ownerID, trackID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	for i, track := range m.tracks {
		if track.ID == trackID && track.OwnerID == ownerID {
			m.tracks = append(m.tracks[:i], m.tracks[i+1:]...)
			return nil
		}
	}
	return store.ErrNotFound
}

func (m *memoryTracks) has(id string) bool {
	_, err := (&memoryTracks{tracks: m.tracks, leaky: true}).ForOwner(context.Background(), "", id)
	return err == nil
}

type fakeObjects struct {
	objects map[string][]byte
	signed  []string
}

func (f *fakeObjects) PresignGet(_ context.Context, key string) (string, time.Time, error) {
	f.signed = append(f.signed, key)
	return "https://music.example.com/nafir-music/" + key + "?X-Amz-Signature=sig", time.Now().Add(time.Hour), nil
}

func (f *fakeObjects) PresignUpload(_ context.Context, key, contentType string, size int64) (storage.Upload, error) {
	return storage.Upload{
		URL:       "https://music.example.com/nafir-music/",
		Fields:    map[string]string{"key": key, "Content-Type": contentType, "policy": "p"},
		ExpiresAt: time.Now().Add(time.Hour),
	}, nil
}

func (f *fakeObjects) Size(_ context.Context, key string) (int64, error) {
	data, ok := f.objects[key]
	if !ok {
		return 0, storage.ErrObjectMissing
	}
	return int64(len(data)), nil
}

func (f *fakeObjects) Head(_ context.Context, key string, n int64) ([]byte, error) {
	data := f.objects[key]
	if int64(len(data)) > n {
		data = data[:n]
	}
	return data, nil
}

func (f *fakeObjects) Remove(_ context.Context, key string) error {
	delete(f.objects, key)
	return nil
}

type tracksAPI struct {
	handler http.Handler
	tracks  *memoryTracks
	objects *fakeObjects
	alice   string
	bob     string
}

func newTracksAPI(t *testing.T, tracks *memoryTracks) tracksAPI {
	t.Helper()
	tokens, err := auth.NewTokens([]byte(strings.Repeat("k", auth.MinSecretBytes)), time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	alice, _, _ := tokens.Issue("alice")
	bob, _, _ := tokens.Issue("bob")
	objects := &fakeObjects{objects: map[string][]byte{}}
	return tracksAPI{
		handler: NewHandler(Config{Tracks: NewTrackHandlers(tracks, objects, tokens, testMaxUpload)}),
		tracks:  tracks,
		objects: objects,
		alice:   alice,
		bob:     bob,
	}
}

func (a tracksAPI) do(t *testing.T, method, path, body, token string) *httptest.ResponseRecorder {
	t.Helper()
	request := httptest.NewRequest(method, path, bytes.NewBufferString(body))
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}
	response := httptest.NewRecorder()
	a.handler.ServeHTTP(response, request)
	return response
}

func (a tracksAPI) get(t *testing.T, path, token string) *httptest.ResponseRecorder {
	return a.do(t, http.MethodGet, path, "", token)
}

func sampleTracks() *memoryTracks {
	return &memoryTracks{tracks: []store.Track{
		{ID: "a1", OwnerID: "alice", Status: store.TrackReady, Title: "Alice song", StorageKey: "users/alice/tracks/a1/song.mp3", ContentType: "audio/mpeg"},
		{ID: "b1", OwnerID: "bob", Status: store.TrackReady, Title: "Bob song", StorageKey: "users/bob/tracks/b1/song.mp3", ContentType: "audio/mpeg"},
	}}
}

func TestListReturnsOnlyOwnTracks(t *testing.T) {
	api := newTracksAPI(t, sampleTracks())

	response := api.get(t, "/api/v1/tracks", api.alice)
	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", response.Code)
	}
	list := decode[trackListResponse](t, response)
	if len(list.Tracks) != 1 || list.Tracks[0].ID != "a1" {
		t.Fatalf("alice should see only a1, got %+v", list.Tracks)
	}
	if strings.Contains(response.Body.String(), "users/") {
		t.Fatal("storage keys must not be exposed")
	}
}

func TestEmptyLibraryIsAnEmptyArray(t *testing.T) {
	api := newTracksAPI(t, &memoryTracks{})
	if body := strings.TrimSpace(api.get(t, "/api/v1/tracks", api.alice).Body.String()); body != `{"tracks":[]}` {
		t.Fatalf("unexpected body %s", body)
	}
}

func TestOwnTrackAndStreamURL(t *testing.T) {
	api := newTracksAPI(t, sampleTracks())

	if response := api.get(t, "/api/v1/tracks/a1", api.alice); response.Code != http.StatusOK {
		t.Fatalf("get: expected 200, got %d", response.Code)
	}
	response := api.get(t, "/api/v1/tracks/a1/stream", api.alice)
	if response.Code != http.StatusOK {
		t.Fatalf("stream: expected 200, got %d", response.Code)
	}
	if response.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("stream URLs must not be cached")
	}
	stream := decode[streamResponse](t, response)
	if !strings.Contains(stream.URL, "users/alice/tracks/a1/") || !stream.ExpiresAt.After(time.Now()) {
		t.Fatalf("unexpected stream response %+v", stream)
	}
}

func TestOtherUsersTracksAreNotFound(t *testing.T) {
	for name, tracks := range map[string]*memoryTracks{
		"scoped store": sampleTracks(),
		"leaky store":  func() *memoryTracks { m := sampleTracks(); m.leaky = true; return m }(),
	} {
		t.Run(name, func(t *testing.T) {
			api := newTracksAPI(t, tracks)
			api.objects.objects["users/bob/tracks/b1/song.mp3"] = []byte("ID3")
			for _, request := range []struct{ method, path string }{
				{http.MethodGet, "/api/v1/tracks/b1"},
				{http.MethodGet, "/api/v1/tracks/b1/stream"},
				{http.MethodPost, "/api/v1/tracks/b1/complete"},
				{http.MethodDelete, "/api/v1/tracks/b1"},
			} {
				expectError(t, api.do(t, request.method, request.path, "", api.alice), http.StatusNotFound, "not_found")
			}
			// Same answer as a track that does not exist at all.
			expectError(t, api.get(t, "/api/v1/tracks/missing", api.alice), http.StatusNotFound, "not_found")
			if len(api.objects.signed) != 0 {
				t.Fatalf("presigned %v for another user", api.objects.signed)
			}
			if !tracks.has("b1") || api.objects.objects["users/bob/tracks/b1/song.mp3"] == nil {
				t.Fatal("alice deleted bob's track")
			}
		})
	}
}

func TestTracksRequireAuthentication(t *testing.T) {
	api := newTracksAPI(t, sampleTracks())
	for _, request := range []struct{ method, path string }{
		{http.MethodGet, "/api/v1/tracks"},
		{http.MethodGet, "/api/v1/tracks/a1"},
		{http.MethodGet, "/api/v1/tracks/a1/stream"},
		{http.MethodPost, "/api/v1/tracks/uploads"},
		{http.MethodPost, "/api/v1/tracks/a1/complete"},
		{http.MethodDelete, "/api/v1/tracks/a1"},
	} {
		expectError(t, api.do(t, request.method, request.path, "", ""), http.StatusUnauthorized, "unauthorized")
		expectError(t, api.do(t, request.method, request.path, "", "forged"), http.StatusUnauthorized, "unauthorized")
	}
}

func (a tracksAPI) createUpload(t *testing.T, body string) createUploadResponse {
	t.Helper()
	response := a.do(t, http.MethodPost, "/api/v1/tracks/uploads", body, a.alice)
	if response.Code != http.StatusCreated {
		t.Fatalf("create upload: expected 201, got %d: %s", response.Code, response.Body.String())
	}
	return decode[createUploadResponse](t, response)
}

func TestUploadLifecycle(t *testing.T) {
	api := newTracksAPI(t, &memoryTracks{})

	created := api.createUpload(t, `{"fileName":"آهنگ من.mp3","sizeBytes":6,"artist":" Artist "}`)
	if created.Track.Title != "آهنگ من" || *created.Track.Artist != "Artist" || created.Track.ContentType != "audio/mpeg" {
		t.Fatalf("unexpected track %+v", created.Track)
	}
	key := created.Upload.Fields["key"]
	if !strings.HasPrefix(key, "users/alice/tracks/"+created.Track.ID+"/") || !strings.HasSuffix(key, "/track.mp3") {
		t.Fatalf("upload key %q is not owner-scoped and sanitized", key)
	}
	id := created.Track.ID

	// A pending track is invisible until it is completed.
	if list := decode[trackListResponse](t, api.get(t, "/api/v1/tracks", api.alice)); len(list.Tracks) != 0 {
		t.Fatalf("pending track listed: %+v", list.Tracks)
	}
	expectError(t, api.get(t, "/api/v1/tracks/"+id+"/stream", api.alice), http.StatusNotFound, "not_found")
	expectError(t, api.do(t, http.MethodPost, "/api/v1/tracks/"+id+"/complete", "", api.alice), http.StatusConflict, "upload_missing")

	api.objects.objects[key] = []byte("ID3\x04\x00\x00")
	completed := api.do(t, http.MethodPost, "/api/v1/tracks/"+id+"/complete", "", api.alice)
	if completed.Code != http.StatusOK {
		t.Fatalf("complete: expected 200, got %d: %s", completed.Code, completed.Body.String())
	}
	if again := api.do(t, http.MethodPost, "/api/v1/tracks/"+id+"/complete", "", api.alice); again.Code != http.StatusOK {
		t.Fatalf("completing twice should be harmless, got %d", again.Code)
	}
	if list := decode[trackListResponse](t, api.get(t, "/api/v1/tracks", api.alice)); len(list.Tracks) != 1 {
		t.Fatalf("completed track not listed: %+v", list.Tracks)
	}

	if response := api.do(t, http.MethodDelete, "/api/v1/tracks/"+id, "", api.alice); response.Code != http.StatusNoContent {
		t.Fatalf("delete: expected 204, got %d", response.Code)
	}
	if api.tracks.has(id) || api.objects.objects[key] != nil {
		t.Fatal("delete left the track or object behind")
	}
}

func TestCompleteRejectsFilesThatAreNotTheDeclaredAudio(t *testing.T) {
	for name, content := range map[string]string{
		"wrong size":        "ID3\x04",
		"not an audio file": "<html>",
	} {
		t.Run(name, func(t *testing.T) {
			api := newTracksAPI(t, &memoryTracks{})
			created := api.createUpload(t, `{"fileName":"song.mp3","sizeBytes":6}`)
			key := created.Upload.Fields["key"]
			api.objects.objects[key] = []byte(content)

			response := api.do(t, http.MethodPost, "/api/v1/tracks/"+created.Track.ID+"/complete", "", api.alice)
			expectError(t, response, http.StatusUnprocessableEntity, "invalid_audio")
			if api.tracks.has(created.Track.ID) || api.objects.objects[key] != nil {
				t.Fatal("rejected upload was not cleaned up")
			}
		})
	}
}

func TestCreateUploadValidation(t *testing.T) {
	api := newTracksAPI(t, &memoryTracks{})
	cases := []struct {
		name, body string
		status     int
		code       string
	}{
		{"unknown field", `{"fileName":"a.mp3","sizeBytes":1,"owner":"bob"}`, http.StatusBadRequest, "invalid_json"},
		{"not audio", `{"fileName":"notes.txt","sizeBytes":1}`, http.StatusUnsupportedMediaType, "unsupported_format"},
		{"empty file", `{"fileName":"a.mp3","sizeBytes":0}`, http.StatusRequestEntityTooLarge, "invalid_size"},
		{"too large", `{"fileName":"a.mp3","sizeBytes":1001}`, http.StatusRequestEntityTooLarge, "invalid_size"},
		{"long title", `{"fileName":"a.mp3","sizeBytes":1,"title":"` + strings.Repeat("x", 201) + `"}`, http.StatusBadRequest, "invalid_metadata"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			expectError(t, api.do(t, http.MethodPost, "/api/v1/tracks/uploads", tc.body, api.alice), tc.status, tc.code)
		})
	}
	if len(api.tracks.tracks) != 0 {
		t.Fatalf("invalid requests created tracks: %+v", api.tracks.tracks)
	}
}
