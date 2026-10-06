package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

func TestHistoryAPI(t *testing.T) {
	pool := collabTestPool(t)
	ctx := context.Background()
	users := store.NewUsers(pool)
	tracks := store.NewTracks(pool)
	playlists := store.NewPlaylists(pool)
	tokens, _ := auth.NewTokens([]byte(strings.Repeat("k", auth.MinSecretBytes)), time.Hour)
	rate := NewRateLimiter(RateLimit{Requests: 4, Window: time.Hour}, 100)
	handler := NewHandler(Config{History: NewHistoryHandlers(store.NewHistory(pool), tokens, rate)})

	alice, _ := users.Create(ctx, "alice@example.com", "hash")
	bob, _ := users.Create(ctx, "bob@example.com", "hash")
	aliceToken, _, _ := tokens.Issue(alice.ID)
	bobToken, _, _ := tokens.Issue(bob.ID)
	aliceTrack, _ := tracks.Create(ctx, alice.ID, store.NewTrack{Title: "mine", FileName: "a.mp3", ContentType: "audio/mpeg", SizeBytes: 1})
	bobTrack, _ := tracks.Create(ctx, bob.ID, store.NewTrack{Title: "his", FileName: "b.mp3", ContentType: "audio/mpeg", SizeBytes: 1})
	together, _ := playlists.Create(ctx, bob.ID, "together")
	_ = playlists.ReplaceTracks(ctx, bob.ID, together.ID, []string{bobTrack.ID})
	_, _ = playlists.SetCollabToken(ctx, bob.ID, together.ID, ptrTo("join"))
	_, _ = playlists.Join(ctx, alice.ID, "join")

	call := func(method, path, token string, body any) *httptest.ResponseRecorder {
		t.Helper()
		var encoded []byte
		if body != nil {
			encoded, _ = json.Marshal(body)
		}
		request := httptest.NewRequest(method, path, bytes.NewReader(encoded))
		if token != "" {
			request.Header.Set("Authorization", "Bearer "+token)
		}
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		return response
	}
	list := func(token, query string) historyResponse {
		t.Helper()
		response := call("GET", "/api/v1/history"+query, token, nil)
		if response.Code != http.StatusOK {
			t.Fatalf("list = %d %s", response.Code, response.Body)
		}
		var body historyResponse
		if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		return body
	}

	// Signing in is required for every history call.
	for _, method := range []string{"GET", "POST", "DELETE"} {
		if code := call(method, "/api/v1/history", "", map[string]string{"trackId": aliceTrack.ID}).Code; code != http.StatusUnauthorized {
			t.Errorf("%s without a token = %d", method, code)
		}
	}

	// Someone else's track can't be recorded, except through a playlist
	// the user is in; neither tells a missing track from a forbidden one.
	if code := call("POST", "/api/v1/history", bobToken, map[string]string{"trackId": aliceTrack.ID}).Code; code != http.StatusNotFound {
		t.Fatalf("bob records alice's track = %d", code)
	}
	if code := call("POST", "/api/v1/history", aliceToken, map[string]string{"trackId": aliceTrack.ID}).Code; code != http.StatusNoContent {
		t.Fatalf("record own = %d", code)
	}
	if code := call("POST", "/api/v1/history", aliceToken, map[string]any{"trackId": bobTrack.ID, "playlistId": together.ID}).Code; code != http.StatusNoContent {
		t.Fatalf("record member track = %d", code)
	}
	if code := call("POST", "/api/v1/history", aliceToken, map[string]any{"trackId": aliceTrack.ID, "extra": 1}).Code; code != http.StatusBadRequest {
		t.Fatalf("unknown field = %d", code)
	}

	got := list(aliceToken, "")
	if len(got.Entries) != 2 {
		t.Fatalf("entries = %+v", got.Entries)
	}
	member, own := got.Entries[0], got.Entries[1]
	if member.Track.ID != bobTrack.ID || member.PlaylistID == nil || *member.PlaylistID != together.ID ||
		member.Track.AddedBy == nil || strings.Contains(*member.Track.AddedBy, "bob@example.com") {
		t.Fatalf("member entry = %+v", member)
	}
	if own.Track.ID != aliceTrack.ID || own.PlaylistID != nil || own.Track.AddedBy != nil {
		t.Fatalf("own entry = %+v", own)
	}
	if limited := list(aliceToken, "?limit=1"); len(limited.Entries) != 1 {
		t.Fatalf("limit=1 gave %d", len(limited.Entries))
	}
	for _, bad := range []string{"?limit=0", "?limit=-3", "?limit=x"} {
		if code := call("GET", "/api/v1/history"+bad, aliceToken, nil).Code; code != http.StatusBadRequest {
			t.Errorf("%s = %d", bad, code)
		}
	}
	if huge := list(aliceToken, "?limit=100000"); len(huge.Entries) != 2 {
		t.Fatalf("a huge limit = %d entries", len(huge.Entries))
	}
	if other := list(bobToken, ""); len(other.Entries) != 0 {
		t.Fatalf("bob sees %+v", other.Entries)
	}

	// The fourth recording in the window is refused with Retry-After.
	call("POST", "/api/v1/history", aliceToken, map[string]string{"trackId": aliceTrack.ID})
	limited := call("POST", "/api/v1/history", aliceToken, map[string]string{"trackId": aliceTrack.ID})
	if limited.Code != http.StatusTooManyRequests || limited.Header().Get("Retry-After") == "" {
		t.Fatalf("rate limit = %d %q", limited.Code, limited.Header().Get("Retry-After"))
	}
	// Other people have their own allowance.
	if code := call("POST", "/api/v1/history", bobToken, map[string]string{"trackId": bobTrack.ID}).Code; code != http.StatusNoContent {
		t.Fatalf("bob after alice is limited = %d", code)
	}

	// Clearing only touches the caller's history.
	if code := call("DELETE", "/api/v1/history", aliceToken, nil).Code; code != http.StatusNoContent {
		t.Fatalf("clear = %d", code)
	}
	if after := list(aliceToken, ""); len(after.Entries) != 0 {
		t.Fatalf("after clear = %+v", after.Entries)
	}
	if bobs := list(bobToken, ""); len(bobs.Entries) != 1 {
		t.Fatalf("bob's history after alice cleared = %+v", bobs.Entries)
	}
}

func ptrTo(s string) *string { return &s }
