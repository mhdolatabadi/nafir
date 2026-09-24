package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

type memoryTracks struct {
	tracks []store.Track
	// leaky ignores the owner, to prove the handler does not rely on the store alone.
	leaky bool
}

func (m *memoryTracks) ListForOwner(_ context.Context, ownerID string) ([]store.Track, error) {
	var owned []store.Track
	for _, track := range m.tracks {
		if track.OwnerID == ownerID {
			owned = append(owned, track)
		}
	}
	return owned, nil
}

func (m *memoryTracks) ForOwner(_ context.Context, ownerID, trackID string) (store.Track, error) {
	for _, track := range m.tracks {
		if track.ID == trackID && (m.leaky || track.OwnerID == ownerID) {
			return track, nil
		}
	}
	return store.Track{}, store.ErrNotFound
}

type fakePresigner struct{ signed []string }

func (f *fakePresigner) PresignGet(_ context.Context, key string) (string, time.Time, error) {
	f.signed = append(f.signed, key)
	return "https://music.example.com/nafir-music/" + key + "?X-Amz-Signature=sig", time.Now().Add(time.Hour), nil
}

type tracksAPI struct {
	handler   http.Handler
	presigner *fakePresigner
	alice     string
	bob       string
}

func newTracksAPI(t *testing.T, tracks *memoryTracks) tracksAPI {
	t.Helper()
	tokens, err := auth.NewTokens([]byte(strings.Repeat("k", auth.MinSecretBytes)), time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	alice, _, _ := tokens.Issue("alice")
	bob, _, _ := tokens.Issue("bob")
	presigner := &fakePresigner{}
	return tracksAPI{
		handler:   NewHandler(Config{Tracks: NewTrackHandlers(tracks, presigner, tokens)}),
		presigner: presigner,
		alice:     alice,
		bob:       bob,
	}
}

func (a tracksAPI) get(t *testing.T, path, token string) *httptest.ResponseRecorder {
	t.Helper()
	request := httptest.NewRequest(http.MethodGet, path, nil)
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}
	response := httptest.NewRecorder()
	a.handler.ServeHTTP(response, request)
	return response
}

func sampleTracks() *memoryTracks {
	return &memoryTracks{tracks: []store.Track{
		{ID: "a1", OwnerID: "alice", Title: "Alice song", StorageKey: "users/alice/tracks/a1/song.mp3", ContentType: "audio/mpeg"},
		{ID: "b1", OwnerID: "bob", Title: "Bob song", StorageKey: "users/bob/tracks/b1/song.mp3", ContentType: "audio/mpeg"},
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
			for _, path := range []string{"/api/v1/tracks/b1", "/api/v1/tracks/b1/stream"} {
				expectError(t, api.get(t, path, api.alice), http.StatusNotFound, "not_found")
			}
			// Same answer as a track that does not exist at all.
			expectError(t, api.get(t, "/api/v1/tracks/missing", api.alice), http.StatusNotFound, "not_found")
			if len(api.presigner.signed) != 0 {
				t.Fatalf("presigned %v for another user", api.presigner.signed)
			}
		})
	}
}

func TestTracksRequireAuthentication(t *testing.T) {
	api := newTracksAPI(t, sampleTracks())
	for _, path := range []string{"/api/v1/tracks", "/api/v1/tracks/a1", "/api/v1/tracks/a1/stream"} {
		expectError(t, api.get(t, path, ""), http.StatusUnauthorized, "unauthorized")
		expectError(t, api.get(t, path, "forged"), http.StatusUnauthorized, "unauthorized")
	}
}
