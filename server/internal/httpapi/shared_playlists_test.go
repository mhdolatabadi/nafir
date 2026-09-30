package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

// sharingStore holds one playlist owned by alice with one track in it.
type sharingStore struct {
	token   *string
	tracks  []store.Track
	outside store.Track
}

func (s *sharingStore) ListForOwner(context.Context, string) ([]store.Playlist, error) {
	return nil, nil
}
func (s *sharingStore) ForOwner(context.Context, string, string) (store.Playlist, error) {
	return store.Playlist{}, store.ErrNotFound
}
func (s *sharingStore) Create(context.Context, string, string) (store.Playlist, error) {
	return store.Playlist{}, errors.New("unused")
}
func (s *sharingStore) Rename(context.Context, string, string, string) (store.Playlist, error) {
	return store.Playlist{}, errors.New("unused")
}
func (s *sharingStore) ReplaceTracks(context.Context, string, string, []string) error {
	return errors.New("unused")
}
func (s *sharingStore) Delete(context.Context, string, string) error { return errors.New("unused") }

func (s *sharingStore) Share(_ context.Context, ownerID, playlistID, token string) (store.Playlist, error) {
	if ownerID != "alice" || playlistID != "p1" {
		return store.Playlist{}, store.ErrNotFound
	}
	if s.token == nil {
		s.token = &token
	}
	return store.Playlist{ID: "p1", OwnerID: "alice", ShareToken: s.token}, nil
}

func (s *sharingStore) Unshare(_ context.Context, ownerID, playlistID string) error {
	if ownerID != "alice" || playlistID != "p1" {
		return store.ErrNotFound
	}
	s.token = nil
	return nil
}

func (s *sharingStore) ForShareToken(_ context.Context, token string) (store.SharedPlaylist, error) {
	if s.token == nil || *s.token != token {
		return store.SharedPlaylist{}, store.ErrNotFound
	}
	return store.SharedPlaylist{
		Playlist:   store.Playlist{ID: "p1", OwnerID: "alice", Name: "mix", Tracks: s.tracks},
		OwnerEmail: "alice@example.com",
	}, nil
}

func (s *sharingStore) SharedTrack(_ context.Context, token, trackID string) (store.Track, error) {
	if s.token == nil || *s.token != token {
		return store.Track{}, store.ErrNotFound
	}
	for _, t := range s.tracks {
		if t.ID == trackID {
			return t, nil
		}
	}
	return store.Track{}, store.ErrNotFound
}

func (s *sharingStore) SaveShared(_ context.Context, userID, token string, maxOwnerBytes int64, _ store.ObjectCopier) (store.Playlist, error) {
	if s.token == nil || *s.token != token {
		return store.Playlist{}, store.ErrNotFound
	}
	if userID == "alice" {
		return store.Playlist{}, store.ErrOwnPlaylist
	}
	if maxOwnerBytes < 100 {
		return store.Playlist{}, store.ErrQuotaExceeded
	}
	return store.Playlist{ID: "copy", OwnerID: userID, Name: "mix", Tracks: s.tracks}, nil
}

type noCopies struct{}

func (noCopies) Copy(context.Context, string, string) error { return nil }
func (noCopies) Remove(context.Context, string) error       { return nil }

type fixedPresigner struct{}

func (fixedPresigner) PresignGet(_ context.Context, key string) (string, time.Time, error) {
	return "https://music.example.com/nafir-music/" + key + "?sig", time.Now().Add(time.Hour), nil
}

func TestSharingAPlaylistEndToEnd(t *testing.T) {
	tokens, _ := auth.NewTokens([]byte(strings.Repeat("k", auth.MinSecretBytes)), time.Hour)
	alice, _, _ := tokens.Issue("alice")
	bob, _, _ := tokens.Issue("bob")
	data := &sharingStore{
		tracks:  []store.Track{{ID: "t1", Title: "in", StorageKey: "users/alice/tracks/t1/a.mp3", Status: store.TrackReady}},
		outside: store.Track{ID: "t2"},
	}
	handler := NewHandler(Config{Playlists: NewPlaylistHandlers(data, tokens).WithSharing(data, fixedPresigner{}, SavePolicy{Objects: noCopies{}, MaxOwnerBytes: 1000, Enabled: true})})
	call := func(method, path, token string) *httptest.ResponseRecorder {
		request := httptest.NewRequest(method, path, nil)
		if token != "" {
			request.Header.Set("Authorization", "Bearer "+token)
		}
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		return response
	}

	if response := call(http.MethodPost, "/api/v1/playlists/p1/share", bob); response.Code != http.StatusNotFound {
		t.Fatalf("bob sharing alice's playlist = %d", response.Code)
	}
	response := call(http.MethodPost, "/api/v1/playlists/p1/share", alice)
	var shared shareResponse
	json.NewDecoder(response.Body).Decode(&shared)
	if response.Code != http.StatusOK || !validShareToken(shared.ShareToken) {
		t.Fatalf("share = %d %+v", response.Code, shared)
	}
	link := "/api/v1/shared-playlists/" + shared.ShareToken

	if response := call(http.MethodGet, link, ""); response.Code != http.StatusUnauthorized {
		t.Fatalf("viewing signed out = %d", response.Code)
	}
	response = call(http.MethodGet, link, bob)
	var view sharedPlaylistResponse
	json.NewDecoder(response.Body).Decode(&view)
	if response.Code != http.StatusOK || view.Name != "mix" || view.Owner != "a***@example.com" ||
		view.IsOwner || view.TrackCount != 1 || strings.Contains(response.Body.String(), "users/alice") {
		t.Fatalf("bob's view = %d %+v", response.Code, view)
	}
	if response := call(http.MethodGet, link, alice); !strings.Contains(response.Body.String(), `"isOwner":true`) {
		t.Fatalf("owner's view = %s", response.Body)
	}

	if response := call(http.MethodGet, link+"/tracks/t1/stream", bob); response.Code != http.StatusOK {
		t.Fatalf("stream a track in the playlist = %d", response.Code)
	}
	if response := call(http.MethodGet, link+"/tracks/t2/stream", bob); response.Code != http.StatusNotFound {
		t.Fatalf("stream a track outside the playlist = %d", response.Code)
	}
	for _, bad := range []string{"not-a-token", strings.Repeat("A", 22), "abc%21def"} {
		if response := call(http.MethodGet, "/api/v1/shared-playlists/"+bad, bob); response.Code != http.StatusNotFound {
			t.Fatalf("malformed link %q = %d", bad, response.Code)
		}
	}

	if response := call(http.MethodDelete, "/api/v1/playlists/p1/share", bob); response.Code != http.StatusNotFound {
		t.Fatalf("bob unsharing = %d", response.Code)
	}
	if response := call(http.MethodDelete, "/api/v1/playlists/p1/share", alice); response.Code != http.StatusNoContent {
		t.Fatalf("unshare = %d", response.Code)
	}
	if response := call(http.MethodGet, link, bob); response.Code != http.StatusNotFound {
		t.Fatalf("revoked link = %d", response.Code)
	}
	if response := call(http.MethodGet, link+"/tracks/t1/stream", bob); response.Code != http.StatusNotFound {
		t.Fatalf("stream after revoking = %d", response.Code)
	}
}

func TestSavingASharedPlaylistEndpoint(t *testing.T) {
	tokens, _ := auth.NewTokens([]byte(strings.Repeat("k", auth.MinSecretBytes)), time.Hour)
	alice, _, _ := tokens.Issue("alice")
	bob, _, _ := tokens.Issue("bob")
	token := strings.Repeat("A", 22)
	data := &sharingStore{token: &token, tracks: []store.Track{{ID: "t1", Title: "in"}}}
	serve := func(policy SavePolicy, user string) *httptest.ResponseRecorder {
		handler := NewHandler(Config{Playlists: NewPlaylistHandlers(data, tokens).WithSharing(data, fixedPresigner{}, policy)})
		request := httptest.NewRequest(http.MethodPost, "/api/v1/shared-playlists/"+token+"/save", nil)
		if user != "" {
			request.Header.Set("Authorization", "Bearer "+user)
		}
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		return response
	}
	open := SavePolicy{Objects: noCopies{}, MaxOwnerBytes: 1000, Enabled: true}

	if response := serve(open, ""); response.Code != http.StatusUnauthorized {
		t.Fatalf("signed out = %d", response.Code)
	}
	response := serve(open, bob)
	var saved playlistResponse
	json.NewDecoder(response.Body).Decode(&saved)
	if response.Code != http.StatusCreated || saved.ID != "copy" || len(saved.Tracks) != 1 {
		t.Fatalf("save = %d %+v", response.Code, saved)
	}
	if response := serve(open, alice); response.Code != http.StatusConflict {
		t.Fatalf("owner saving their own = %d", response.Code)
	}
	if response := serve(SavePolicy{Objects: noCopies{}, MaxOwnerBytes: 10, Enabled: true}, bob); response.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("over quota = %d", response.Code)
	}
	if response := serve(SavePolicy{Objects: noCopies{}, MaxOwnerBytes: 1000}, bob); response.Code != http.StatusServiceUnavailable {
		t.Fatalf("uploads disabled = %d", response.Code)
	}
}
