package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/linkimport"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

type fakeLinkImporter struct {
	delay      time.Duration
	err        error
	urls       []string
	candidates []linkimport.Candidate
}

func (f *fakeLinkImporter) Submit(_ context.Context, userID, rawURL string) (store.BotImport, error) {
	f.urls = append(f.urls, rawURL)
	if f.err != nil {
		return store.BotImport{}, f.err
	}
	return store.BotImport{
		ID: "i1", UserID: userID, FileID: "https://cdn.example.ir/dl/private-token/song.mp3",
		FileName: "song.mp3", State: store.ImportQueued, CreatedAt: time.Now(),
	}, nil
}

func (f *fakeLinkImporter) Preview(ctx context.Context, _ string, rawURL string) ([]linkimport.Candidate, error) {
	if f.delay > 0 {
		select {
		case <-time.After(f.delay):
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
	f.urls = append(f.urls, rawURL)
	if f.err != nil {
		return nil, f.err
	}
	return f.candidates, nil
}

func (f *fakeLinkImporter) Recent(context.Context, string) ([]store.BotImport, error) {
	return []store.BotImport{{ID: "i1", FileID: "https://cdn.example.ir/x.mp3", FileName: "x.mp3", State: store.ImportDone}}, nil
}

func TestLinkImportAPI(t *testing.T) {
	tokens, _ := auth.NewTokens([]byte(strings.Repeat("k", auth.MinSecretBytes)), time.Hour)
	token, _, _ := tokens.Issue("u1")
	audioURL, _ := url.Parse("https://cdn.example.ir/dl/private-token/song.mp3")
	importer := &fakeLinkImporter{candidates: []linkimport.Candidate{{
		URL: audioURL, FileName: "song.mp3", SizeBytes: 1234,
	}}}
	handler := NewHandler(Config{LinkImports: NewLinkImportHandlers(importer, tokens,
		NewRateLimiter(RateLimit{Requests: 20, Window: time.Minute}, 100))})
	submit := func(body string, auth bool) *httptest.ResponseRecorder {
		request := httptest.NewRequest(http.MethodPost, "/api/v1/imports/link", strings.NewReader(body))
		if auth {
			request.Header.Set("Authorization", "Bearer "+token)
		}
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		return response
	}

	if code := submit(`{"url":"https://x.ir/a"}`, false).Code; code != http.StatusUnauthorized {
		t.Fatalf("anonymous = %d", code)
	}
	if code := submit(`{"link":"x"}`, true).Code; code != http.StatusBadRequest {
		t.Fatalf("unknown field = %d", code)
	}
	response := submit(`{"url":"https://music.example.ir/song/1"}`, true)
	var created linkImportResponse
	json.NewDecoder(response.Body).Decode(&created)
	// Only the site is echoed, never the link, which may carry a token.
	if response.Code != http.StatusAccepted || created.Site != "cdn.example.ir" || created.State != "queued" ||
		strings.Contains(response.Body.String(), "private-token") {
		t.Fatalf("submit = %d %+v", response.Code, created)
	}

	preview := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/api/v1/imports/link/preview", strings.NewReader(`{"url":"https://music.example.ir/song/1"}`))
	request.Header.Set("Authorization", "Bearer "+token)
	handler.ServeHTTP(preview, request)
	if preview.Code != http.StatusOK ||
		!strings.Contains(preview.Body.String(), `"fileName":"song.mp3"`) ||
		!strings.Contains(preview.Body.String(), `"url":"https://cdn.example.ir/dl/private-token/song.mp3"`) {
		t.Fatalf("preview = %d %s", preview.Code, preview.Body.String())
	}

	for _, tc := range []struct {
		err  error
		code int
		body string
	}{
		{linkimport.ErrInvalidURL, http.StatusBadRequest, "invalid_url"},
		{linkimport.ErrBlocked, http.StatusBadRequest, "blocked_url"},
		{linkimport.ErrUnreachable, http.StatusBadGateway, "unreachable"},
		{linkimport.ErrNoAudio, http.StatusUnprocessableEntity, "no_audio"},
		{linkimport.ErrUnsupported, http.StatusUnsupportedMediaType, "unsupported_format"},
		{linkimport.ErrTooLarge, http.StatusRequestEntityTooLarge, "too_large"},
		{linkimport.ErrDuplicate, http.StatusConflict, "duplicate_import"},
		{linkimport.ErrTooMany, http.StatusTooManyRequests, "too_many_imports"},
		{linkimport.ErrDisabled, http.StatusServiceUnavailable, "uploads_disabled"},
		{linkimport.ErrTooLong, http.StatusUnprocessableEntity, "too_long"},
		{linkimport.ErrMetadataOnly, http.StatusUnprocessableEntity, "metadata_only"},
		{errors.New("boom"), http.StatusInternalServerError, "internal_error"},
	} {
		importer.err = tc.err
		response := submit(`{"url":"https://x.ir/a"}`, true)
		if response.Code != tc.code || !strings.Contains(response.Body.String(), tc.body) {
			t.Errorf("%v = %d %s", tc.err, response.Code, response.Body.String())
		}
	}

	request = httptest.NewRequest(http.MethodGet, "/api/v1/imports/link", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	list := httptest.NewRecorder()
	handler.ServeHTTP(list, request)
	if list.Code != http.StatusOK || !strings.Contains(list.Body.String(), `"site":"cdn.example.ir"`) {
		t.Fatalf("list = %d %s", list.Code, list.Body.String())
	}
}

type fakeSpotifyImporter struct {
	result linkimport.SpotifyResult
	err    error
}

func (f *fakeSpotifyImporter) Import(context.Context, string, string) (linkimport.SpotifyResult, error) {
	return f.result, f.err
}

func TestSpotifyImportAPI(t *testing.T) {
	tokens, _ := auth.NewTokens([]byte(strings.Repeat("k", auth.MinSecretBytes)), time.Hour)
	token, _, _ := tokens.Issue("u1")
	spotify := &fakeSpotifyImporter{result: linkimport.SpotifyResult{
		Name:     "Road Trip",
		Playlist: &store.Playlist{ID: "pl1"},
		Matched:  []linkimport.SpotifyMatch{{Item: linkimport.SpotifyItem{Title: "Hello", Artists: []string{"Adele"}}, TrackID: "t1"}},
		Missing:  []linkimport.SpotifyItem{{Title: "Gone"}},
	}}
	handler := NewHandler(Config{LinkImports: NewLinkImportHandlers(&fakeLinkImporter{}, tokens, nil).WithSpotify(spotify)})
	post := func(auth bool) *httptest.ResponseRecorder {
		request := httptest.NewRequest(http.MethodPost, "/api/v1/imports/spotify",
			strings.NewReader(`{"url":"https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"}`))
		if auth {
			request.Header.Set("Authorization", "Bearer "+token)
		}
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		return response
	}
	if code := post(false).Code; code != http.StatusUnauthorized {
		t.Fatalf("anonymous = %d", code)
	}
	response := post(true)
	var body struct {
		Name       string `json:"name"`
		PlaylistID string `json:"playlistId"`
		Matched    []struct {
			Title   string   `json:"title"`
			Artists []string `json:"artists"`
			TrackID string   `json:"trackId"`
		} `json:"matched"`
		Missing []struct {
			Title   string   `json:"title"`
			Artists []string `json:"artists"`
		} `json:"missing"`
	}
	json.NewDecoder(response.Body).Decode(&body)
	if response.Code != http.StatusCreated || body.PlaylistID != "pl1" || body.Name != "Road Trip" ||
		len(body.Matched) != 1 || body.Matched[0].TrackID != "t1" || len(body.Missing) != 1 || body.Missing[0].Artists == nil {
		t.Fatalf("import = %d %+v", response.Code, body)
	}

	spotify.result = linkimport.SpotifyResult{Name: "Road Trip", Missing: []linkimport.SpotifyItem{{Title: "Gone"}}}
	response = post(true)
	if response.Code != http.StatusOK || strings.Contains(response.Body.String(), "playlistId") {
		t.Fatalf("no matches = %d %s", response.Code, response.Body.String())
	}

	spotify.err = linkimport.ErrNoTracks
	if response := post(true); response.Code != http.StatusUnprocessableEntity || !strings.Contains(response.Body.String(), "no_tracks") {
		t.Fatalf("no tracks = %d %s", response.Code, response.Body.String())
	}
}

func TestLinkPreviewExtendsOnlyItsWriteDeadline(t *testing.T) {
	tokens, _ := auth.NewTokens([]byte(strings.Repeat("k", auth.MinSecretBytes)), time.Hour)
	token, _, _ := tokens.Issue("owner")
	importer := &fakeLinkImporter{delay: 80 * time.Millisecond}
	server := httptest.NewUnstartedServer(NewHandler(Config{LinkImports: NewLinkImportHandlers(importer, tokens, nil)}))
	server.Config.WriteTimeout = 20 * time.Millisecond
	server.Start()
	defer server.Close()
	req, _ := http.NewRequest(http.MethodPost, server.URL+"/api/v1/imports/link/preview", strings.NewReader(`{"url":"https://youtu.be/BaW_jenozKc"}`))
	req.Header.Set("Authorization", "Bearer "+token)
	response, err := server.Client().Do(req)
	if err != nil {
		t.Fatal("preview hit the normal server write timeout:", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		t.Fatal(response.StatusCode)
	}
}
