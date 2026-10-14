package linkimport

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/mhdolatabadi/nafir/server/internal/store"
)

const spotifyPlaylistPage = `<html><head><title>Embed</title></head><body>
<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"state":{"data":{"entity":{
"type":"playlist","name":"Road Trip","trackList":[
{"title":"Bohemian Rhapsody - Remastered 2011","subtitle":"Queen"},
{"title":"Hello","subtitle":"Adele"},
{"title":"سلام","subtitle":"Singer A, Singer B"},
{"title":"Missing Song","subtitle":"Nobody"}
]}}}}}}</script></body></html>`

const spotifyTrackPage = `<html><body><script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"state":{"data":{"entity":{
"type":"track","name":"Hello","artists":[{"name":"Adele"}]}}}}}}</script></body></html>`

func fakeSpotify(t *testing.T) (*SpotifyReader, *httptest.Server) {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		switch r.URL.Path {
		case "/embed/playlist/37i9dQZF1DXcBWIGoYBM5M":
			fmt.Fprint(w, spotifyPlaylistPage)
		case "/embed/track/4uLU6hMCjMI75M1A2tKUQC":
			fmt.Fprint(w, spotifyTrackPage)
		case "/embed/track/0000000000000000000000":
			fmt.Fprint(w, "<html>changed layout</html>")
		case "/embed/album/1111111111111111111111":
			fmt.Fprint(w, "<html>changed layout</html>")
		case "/oembed":
			if r.URL.Query().Get("url") != "https://open.spotify.com/track/0000000000000000000000" {
				http.NotFound(w, r)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprint(w, `{"title":"From oEmbed"}`)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(server.Close)
	reader := NewSpotifyReader(testFetcher(server))
	reader.base, _ = url.Parse(server.URL)
	return reader, server
}

func spotifyLink(t *testing.T, raw string) SocialLink {
	t.Helper()
	link, ok, err := DetectSocial(mustParse(t, raw))
	if !ok || err != nil {
		t.Fatalf("DetectSocial(%s) = %v, %v", raw, ok, err)
	}
	return link
}

func TestSpotifyReader(t *testing.T) {
	reader, _ := fakeSpotify(t)
	ctx := context.Background()

	list, err := reader.Read(ctx, spotifyLink(t, "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"))
	if err != nil || list.Name != "Road Trip" || len(list.Tracks) != 4 {
		t.Fatalf("playlist = %+v, %v", list, err)
	}
	if got := list.Tracks[2].Artists; len(got) != 2 || got[0] != "Singer A" || got[1] != "Singer B" {
		t.Fatalf("artists = %q", got)
	}

	list, err = reader.Read(ctx, spotifyLink(t, "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"))
	if err != nil || len(list.Tracks) != 1 || list.Tracks[0].Title != "Hello" || list.Tracks[0].Artists[0] != "Adele" {
		t.Fatalf("track = %+v, %v", list, err)
	}

	// Without embed data, a track still has its oEmbed title.
	list, err = reader.Read(ctx, spotifyLink(t, "https://open.spotify.com/track/0000000000000000000000"))
	if err != nil || len(list.Tracks) != 1 || list.Tracks[0].Title != "From oEmbed" {
		t.Fatalf("oembed = %+v, %v", list, err)
	}
	if _, err := reader.Read(ctx, spotifyLink(t, "https://open.spotify.com/album/1111111111111111111111")); !errors.Is(err, ErrNoTracks) {
		t.Fatalf("album without data: %v", err)
	}
	if _, err := reader.Read(ctx, spotifyLink(t, "https://open.spotify.com/album/2222222222222222222222")); !errors.Is(err, ErrUnreachable) {
		t.Fatalf("missing album: %v", err)
	}
}

func TestSpotifyReaderKeepsTheAddressChecks(t *testing.T) {
	_, server := fakeSpotify(t)
	reader := NewSpotifyReader(NewFetcher())
	reader.base, _ = url.Parse(server.URL)
	if _, err := reader.Read(context.Background(), spotifyLink(t, "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M")); !errors.Is(err, ErrBlocked) {
		t.Fatalf("loopback fetch = %v", err)
	}
}

func ptr(s string) *string { return &s }

func TestMatchLibrary(t *testing.T) {
	library := []store.Track{
		{ID: "queen", Title: "Bohemian Rhapsody", Artist: ptr("Queen"), FileName: "a.mp3"},
		{ID: "richie", Title: "Hello", Artist: ptr("Lionel Richie"), FileName: "b.mp3"},
		{ID: "adele", Title: "track", FileName: "Adele - Hello.mp3"},
		{ID: "salam", Title: "سلام", Artist: ptr("Singer B & Someone"), FileName: "c.mp3"},
		{ID: "other", Title: "Other", FileName: "d.mp3"},
	}
	items := []SpotifyItem{
		{Title: "Bohemian Rhapsody - Remastered 2011", Artists: []string{"Queen"}},
		{Title: "Hello", Artists: []string{"Adele"}},
		{Title: "سلام", Artists: []string{"Singer A", "Singer B"}},
		{Title: "Missing Song", Artists: []string{"Nobody"}},
		{Title: "Hello", Artists: []string{"Adele"}},
	}
	matched, missing := MatchLibrary(items, library)
	got := []string{}
	for _, m := range matched {
		got = append(got, m.TrackID)
	}
	if fmt.Sprint(got) != "[queen adele salam]" {
		t.Fatalf("matched = %v", got)
	}
	// The second "Hello" can't reuse Adele's track, and Lionel Richie's is
	// a different song.
	if len(missing) != 2 || missing[0].Title != "Missing Song" || missing[1].Title != "Hello" {
		t.Fatalf("missing = %+v", missing)
	}

	// Persian letter variants and half-spaces don't matter.
	matched, _ = MatchLibrary([]SpotifyItem{{Title: "مي‌خواهم"}}, []store.Track{{ID: "p", Title: "میخواهم", FileName: "p.mp3"}})
	if len(matched) != 1 {
		t.Fatal("Persian variants did not match")
	}
}

// memoryPlaylists records the playlist a Spotify import makes.
type memoryPlaylists struct {
	created    []string
	tracks     map[string][]string
	deleted    []string
	replaceErr error
}

func (m *memoryPlaylists) Create(_ context.Context, ownerID, name string) (store.Playlist, error) {
	m.created = append(m.created, name)
	return store.Playlist{ID: fmt.Sprintf("pl-%d", len(m.created)), OwnerID: ownerID, Name: name}, nil
}
func (m *memoryPlaylists) ReplaceTracks(_ context.Context, _, playlistID string, ids []string) error {
	if m.replaceErr != nil {
		return m.replaceErr
	}
	m.tracks[playlistID] = ids
	return nil
}
func (m *memoryPlaylists) Delete(_ context.Context, _, playlistID string) error {
	m.deleted = append(m.deleted, playlistID)
	return nil
}

type memoryLibrary []store.Track

func (m memoryLibrary) ListForOwner(context.Context, string) ([]store.Track, error) { return m, nil }

func TestSpotifyImporter(t *testing.T) {
	reader, _ := fakeSpotify(t)
	library := memoryLibrary{
		{ID: "queen", Title: "Bohemian Rhapsody", Artist: ptr("Queen"), FileName: "a.mp3"},
		{ID: "adele", Title: "Hello", Artist: ptr("Adele"), FileName: "b.mp3"},
	}
	playlists := &memoryPlaylists{tracks: map[string][]string{}}
	importer := NewSpotifyImporter(reader, library, playlists)
	ctx := context.Background()

	result, err := importer.Import(ctx, "u1", "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=x")
	if err != nil || result.Playlist == nil || result.Name != "Road Trip" || len(result.Missing) != 2 {
		t.Fatalf("import = %+v, %v", result, err)
	}
	if got := playlists.tracks[result.Playlist.ID]; fmt.Sprint(got) != "[queen adele]" {
		t.Fatalf("playlist tracks = %v", got)
	}

	// Nothing matched: no empty playlist is made.
	result, err = NewSpotifyImporter(reader, memoryLibrary{}, playlists).Import(ctx, "u1", "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M")
	if err != nil || result.Playlist != nil || len(result.Missing) != 4 || len(playlists.created) != 1 {
		t.Fatalf("no matches = %+v, %v, created %v", result, err, playlists.created)
	}

	// A playlist that couldn't be filled is removed again.
	failing := &memoryPlaylists{tracks: map[string][]string{}, replaceErr: errors.New("boom")}
	if _, err := NewSpotifyImporter(reader, library, failing).Import(ctx, "u1", "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"); err == nil {
		t.Fatal("replace failure was ignored")
	}
	if fmt.Sprint(failing.deleted) != "[pl-1]" {
		t.Fatalf("deleted = %v", failing.deleted)
	}

	for raw, want := range map[string]error{
		"https://www.youtube.com/watch?v=dQw4w9WgXcQ":            ErrUnsupported,
		"https://open.spotify.com/artist/4uLU6hMCjMI75M1A2tKUQC": ErrUnsupported,
		"https://example.com/":                                   ErrUnsupported,
		"not a link":                                             ErrInvalidURL,
	} {
		if _, err := importer.Import(ctx, "u1", raw); !errors.Is(err, want) {
			t.Errorf("Import(%s) = %v", raw, err)
		}
	}
}
