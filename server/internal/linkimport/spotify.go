package linkimport

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/url"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/mhdolatabadi/nafir/server/internal/store"
	"golang.org/x/net/html"
)

// ErrNoTracks means a Spotify link named no tracks to look for.
var ErrNoTracks = errors.New("the link lists no tracks")

// maxSpotifyTracks bounds how many titles one link may look up.
const maxSpotifyTracks = 500

// SpotifyItem is a title and its artists, as Spotify lists them.
type SpotifyItem struct {
	Title   string
	Artists []string
}

// SpotifyList is what a Spotify track, album or playlist link names.
type SpotifyList struct {
	Kind   string
	Name   string
	Tracks []SpotifyItem
}

// SpotifyReader reads Spotify's public embed pages, through the fetcher's
// address checks, with no account.
type SpotifyReader struct {
	fetcher *Fetcher
	// base is Spotify's origin; tests point it at a fake.
	base *url.URL
}

func NewSpotifyReader(fetcher *Fetcher) *SpotifyReader {
	return &SpotifyReader{fetcher: fetcher, base: &url.URL{Scheme: "https", Host: "open.spotify.com"}}
}

// Read lists the titles a Spotify link names: from the embed page's data,
// or else the oEmbed title for a single track.
func (r *SpotifyReader) Read(ctx context.Context, link SocialLink) (SpotifyList, error) {
	ctx, cancel := context.WithTimeout(ctx, pageTimeout)
	defer cancel()
	list, err := r.readEmbed(ctx, link)
	if err == nil && len(list.Tracks) > 0 {
		return list, nil
	}
	if link.Kind != "track" {
		if err != nil {
			return SpotifyList{}, err
		}
		return SpotifyList{}, ErrNoTracks
	}
	title, oerr := r.readOEmbed(ctx, link)
	if oerr != nil {
		if err != nil {
			return SpotifyList{}, err
		}
		return SpotifyList{}, oerr
	}
	return SpotifyList{Kind: link.Kind, Name: title, Tracks: []SpotifyItem{{Title: title}}}, nil
}

func (r *SpotifyReader) readEmbed(ctx context.Context, link SocialLink) (SpotifyList, error) {
	u := r.base.ResolveReference(&url.URL{Path: "/embed/" + link.Kind + "/" + link.ID})
	resp, err := r.fetcher.get(ctx, u)
	if err != nil {
		return SpotifyList{}, err
	}
	defer resp.Body.Close()
	if mediaType, _, _ := mime.ParseMediaType(resp.Header.Get("Content-Type")); mediaType != "text/html" {
		return SpotifyList{}, ErrUnsupported
	}
	page, err := io.ReadAll(io.LimitReader(resp.Body, maxPageBytes))
	if err != nil {
		return SpotifyList{}, ErrUnreachable
	}
	data := nextData(string(page))
	if data == "" {
		return SpotifyList{}, ErrNoTracks
	}
	var doc struct {
		Props struct {
			PageProps struct {
				State struct {
					Data struct {
						Entity spotifyEntity `json:"entity"`
					} `json:"data"`
				} `json:"state"`
			} `json:"pageProps"`
		} `json:"props"`
	}
	if err := json.Unmarshal([]byte(data), &doc); err != nil {
		return SpotifyList{}, ErrNoTracks
	}
	entity := doc.Props.PageProps.State.Data.Entity
	list := SpotifyList{Kind: link.Kind, Name: firstNonEmpty(entity.Name, entity.Title)}
	if link.Kind == "track" {
		artists := make([]string, 0, len(entity.Artists))
		for _, a := range entity.Artists {
			if a.Name != "" {
				artists = append(artists, a.Name)
			}
		}
		if list.Name != "" {
			list.Tracks = []SpotifyItem{{Title: list.Name, Artists: artists}}
		}
		return list, nil
	}
	for _, t := range entity.TrackList {
		if len(list.Tracks) == maxSpotifyTracks {
			break
		}
		if title := strings.TrimSpace(t.Title); title != "" {
			list.Tracks = append(list.Tracks, SpotifyItem{Title: title, Artists: splitArtists(t.Subtitle)})
		}
	}
	return list, nil
}

type spotifyEntity struct {
	Name    string `json:"name"`
	Title   string `json:"title"`
	Artists []struct {
		Name string `json:"name"`
	} `json:"artists"`
	TrackList []struct {
		Title    string `json:"title"`
		Subtitle string `json:"subtitle"`
	} `json:"trackList"`
}

// nextData returns the page's __NEXT_DATA__ JSON, if any.
func nextData(page string) string {
	tokens := html.NewTokenizer(strings.NewReader(page))
	inData := false
	for {
		switch tokens.Next() {
		case html.ErrorToken:
			return ""
		case html.StartTagToken:
			token := tokens.Token()
			inData = false
			if token.Data == "script" {
				for _, a := range token.Attr {
					if a.Key == "id" && a.Val == "__NEXT_DATA__" {
						inData = true
					}
				}
			}
		case html.TextToken:
			if inData {
				return string(tokens.Text())
			}
		case html.EndTagToken:
			inData = false
		}
	}
}

func (r *SpotifyReader) readOEmbed(ctx context.Context, link SocialLink) (string, error) {
	u := r.base.ResolveReference(&url.URL{Path: "/oembed", RawQuery: url.Values{"url": {link.URL.String()}}.Encode()})
	resp, err := r.fetcher.get(ctx, u)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	var body struct {
		Title string `json:"title"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 64<<10)).Decode(&body); err != nil {
		return "", ErrNoTracks
	}
	if title := strings.TrimSpace(body.Title); title != "" {
		return title, nil
	}
	return "", ErrNoTracks
}

func splitArtists(s string) []string {
	var artists []string
	for _, a := range strings.Split(strings.ReplaceAll(s, " ", " "), ",") {
		if a = strings.TrimSpace(a); a != "" {
			artists = append(artists, a)
		}
	}
	return artists
}

// SpotifyMatch is one Spotify title and the library track found for it.
type SpotifyMatch struct {
	Item    SpotifyItem
	TrackID string
}

// MatchLibrary finds each title in the library. A track matches when its
// title (or the title part of an "Artist - Title" name) is the same, ignoring
// case, punctuation, Persian letter variants and bracketed notes such as
// "(Remastered)". When both sides name an artist, they must share one.
// Matched tracks keep the Spotify order; a track is only used once.
func MatchLibrary(items []SpotifyItem, library []store.Track) (matched []SpotifyMatch, missing []SpotifyItem) {
	type entry struct {
		titles  []string
		artists []string
	}
	entries := make([]entry, len(library))
	for i, t := range library {
		var e entry
		addTitle := func(s string) {
			for _, v := range []string{normalizeTitle(s, false), normalizeTitle(s, true)} {
				if v != "" {
					e.titles = append(e.titles, v)
				}
			}
		}
		addTitle(t.Title)
		stem := strings.TrimSuffix(t.FileName, extOf(t.FileName))
		for _, name := range []string{t.Title, stem} {
			if artist, title, ok := strings.Cut(name, " - "); ok {
				addTitle(title)
				e.artists = append(e.artists, normalizeTitle(artist, true))
			}
		}
		if t.Artist != nil {
			for _, a := range splitArtists(strings.NewReplacer("&", ",", "،", ",", " feat. ", ",", " ft. ", ",").Replace(*t.Artist)) {
				e.artists = append(e.artists, normalizeTitle(a, true))
			}
		}
		entries[i] = e
	}
	used := map[string]bool{}
	for _, item := range items {
		want := []string{normalizeTitle(item.Title, false), normalizeTitle(item.Title, true)}
		artists := make([]string, 0, len(item.Artists))
		for _, a := range item.Artists {
			artists = append(artists, normalizeTitle(a, true))
		}
		best, bestScore := -1, 0
		for i, e := range entries {
			if used[library[i].ID] || !sharesAny(want, e.titles) {
				continue
			}
			score := 1
			switch {
			case len(artists) == 0 || len(e.artists) == 0:
			case sharesAny(artists, e.artists):
				score = 2
			default:
				continue
			}
			if score > bestScore {
				best, bestScore = i, score
			}
		}
		if best < 0 {
			missing = append(missing, item)
			continue
		}
		used[library[best].ID] = true
		matched = append(matched, SpotifyMatch{Item: item, TrackID: library[best].ID})
	}
	return matched, missing
}

func sharesAny(a, b []string) bool {
	for _, x := range a {
		for _, y := range b {
			if x != "" && x == y {
				return true
			}
		}
	}
	return false
}

func extOf(name string) string {
	if i := strings.LastIndexByte(name, '.'); i > 0 && len(name)-i <= 6 {
		return name[i:]
	}
	return ""
}

// normalizeTitle lower-cases s, unifies Arabic and Persian letter variants,
// drops diacritics and punctuation, and with stripNotes also drops bracketed
// parts and a trailing " - Remastered"-style note.
func normalizeTitle(s string, stripNotes bool) string {
	if stripNotes {
		s = stripBracketed(s)
		if head, _, ok := strings.Cut(s, " - "); ok && head != "" {
			s = head
		}
	}
	var b strings.Builder
	space := false
	for _, r := range strings.ToLower(s) {
		switch r {
		case 'ي', 'ى':
			r = 'ی'
		case 'ك':
			r = 'ک'
		case 'ة':
			r = 'ه'
		case 'أ', 'إ', 'آ':
			r = 'ا'
		case 'ؤ':
			r = 'و'
		}
		switch {
		case r == '‌' || r == 'ـ' || unicode.Is(unicode.Mn, r):
			continue
		case unicode.IsLetter(r) || unicode.IsDigit(r):
			if space && b.Len() > 0 {
				b.WriteByte(' ')
			}
			space = false
			b.WriteRune(r)
		default:
			space = true
		}
	}
	return b.String()
}

func stripBracketed(s string) string {
	var b strings.Builder
	depth := 0
	for _, r := range s {
		switch r {
		case '(', '[', '{':
			depth++
		case ')', ']', '}':
			if depth > 0 {
				depth--
			}
		default:
			if depth == 0 {
				b.WriteRune(r)
			}
		}
	}
	return b.String()
}

// SpotifyStore is the library a Spotify import matches against.
type SpotifyStore interface {
	ListForOwner(ctx context.Context, ownerID string) ([]store.Track, error)
}

// PlaylistStore makes the playlist a Spotify import builds.
type PlaylistStore interface {
	Create(ctx context.Context, ownerID, name string) (store.Playlist, error)
	ReplaceTracks(ctx context.Context, userID, playlistID string, trackIDs []string) error
	Delete(ctx context.Context, ownerID, playlistID string) error
}

// SpotifyImporter turns a Spotify link into a playlist of the matching
// tracks the user already has.
type SpotifyImporter struct {
	reader    *SpotifyReader
	tracks    SpotifyStore
	playlists PlaylistStore
}

func NewSpotifyImporter(reader *SpotifyReader, tracks SpotifyStore, playlists PlaylistStore) *SpotifyImporter {
	return &SpotifyImporter{reader: reader, tracks: tracks, playlists: playlists}
}

// SpotifyResult is a finished Spotify import. Playlist is nil when nothing
// matched.
type SpotifyResult struct {
	Name     string
	Playlist *store.Playlist
	Matched  []SpotifyMatch
	Missing  []SpotifyItem
}

const maxPlaylistNameRunes = 200

// Import reads the link, matches its titles and, if any matched, makes a
// playlist named after it.
func (s *SpotifyImporter) Import(ctx context.Context, userID, rawURL string) (SpotifyResult, error) {
	u, err := ParseURL(rawURL)
	if err != nil {
		return SpotifyResult{}, err
	}
	link, ok, err := DetectSocial(u)
	if err != nil {
		return SpotifyResult{}, err
	}
	if !ok || link.Site != SiteSpotify {
		return SpotifyResult{}, ErrUnsupported
	}
	list, err := s.reader.Read(ctx, link)
	if err != nil {
		return SpotifyResult{}, err
	}
	library, err := s.tracks.ListForOwner(ctx, userID)
	if err != nil {
		return SpotifyResult{}, err
	}
	matched, missing := MatchLibrary(list.Tracks, library)
	name := strings.TrimSpace(list.Name)
	if name == "" {
		name = "Spotify"
	}
	if utf8.RuneCountInString(name) > maxPlaylistNameRunes {
		name = string([]rune(name)[:maxPlaylistNameRunes])
	}
	result := SpotifyResult{Name: name, Matched: matched, Missing: missing}
	if len(matched) == 0 {
		return result, nil
	}
	playlist, err := s.playlists.Create(ctx, userID, name)
	if err != nil {
		return SpotifyResult{}, err
	}
	ids := make([]string, len(matched))
	for i, m := range matched {
		ids[i] = m.TrackID
	}
	if err := s.playlists.ReplaceTracks(ctx, userID, playlist.ID, ids); err != nil {
		// Never leave an empty playlist behind.
		if derr := s.playlists.Delete(context.WithoutCancel(ctx), userID, playlist.ID); derr != nil {
			err = errors.Join(err, derr)
		}
		return SpotifyResult{}, err
	}
	playlist.TrackCount = len(ids)
	result.Playlist = &playlist
	return result, nil
}
