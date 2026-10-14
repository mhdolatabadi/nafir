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

func TestTranscriptionAuthorization(t *testing.T) {
	pool := collabTestPool(t)
	ctx := context.Background()
	users := store.NewUsers(pool)
	tracks := store.NewTracks(pool)
	alice, _ := users.Create(ctx, "alice@example.com", "hash")
	bob, _ := users.Create(ctx, "bob@example.com", "hash")
	track, _ := tracks.Create(ctx, alice.ID, store.NewTrack{Title: "مداحی", FileName: "a.mp3", ContentType: "audio/mpeg", SizeBytes: 5})
	tokens, _ := auth.NewTokens([]byte(strings.Repeat("k", auth.MinSecretBytes)), time.Hour)
	aliceToken, _, _ := tokens.Issue(alice.ID)
	bobToken, _, _ := tokens.Issue(bob.ID)
	h := NewLyricsHandlers(nil, tracks, nil, tokens, LyricsLimits{})
	h.Transcriptions = store.NewTranscriptions(pool)
	handler := NewHandler(Config{Lyrics: h})
	for _, tc := range []struct {
		method, token string
		status        int
	}{
		{"POST", "", 401}, {"GET", bobToken, 404}, {"POST", bobToken, 404},
		{"POST", aliceToken, 202}, {"GET", aliceToken, 200},
	} {
		req := httptest.NewRequest(tc.method, "/api/v1/tracks/"+track.ID+"/transcription", nil)
		if tc.token != "" {
			req.Header.Set("Authorization", "Bearer "+tc.token)
		}
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, req)
		if response.Code != tc.status {
			t.Fatalf("%s: got %d body=%s", tc.method, response.Code, response.Body)
		}
	}
	h.Transcriptions = nil
	req := httptest.NewRequest(http.MethodPost, "/api/v1/tracks/"+track.ID+"/transcription", nil)
	req.Header.Set("Authorization", "Bearer "+aliceToken)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, req)
	if response.Code != 503 || !strings.Contains(response.Body.String(), "transcription_disabled") {
		t.Fatal(response)
	}
}
