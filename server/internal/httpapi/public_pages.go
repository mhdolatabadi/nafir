package httpapi

import (
	"bytes"
	"embed"
	"encoding/xml"
	"errors"
	"fmt"
	"html/template"
	"net/http"
	"strings"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/bot"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

//go:embed public/*.html public/nafir.png
var publicFiles embed.FS

var publicTemplates = map[string]*template.Template{
	"home":     template.Must(template.ParseFS(publicFiles, "public/layout.html", "public/home.html")),
	"playlist": template.Must(template.ParseFS(publicFiles, "public/layout.html", "public/playlist.html")),
	"missing":  template.Must(template.ParseFS(publicFiles, "public/layout.html", "public/missing.html")),
	"privacy":  template.Must(template.ParseFS(publicFiles, "public/layout.html", "public/privacy.html")),
	"delete":   template.Must(template.ParseFS(publicFiles, "public/layout.html", "public/delete_account.html")),
}

const (
	// publicListSize is how many popular playlists the front page shows.
	publicListSize = 100
	// sitemapSize caps the playlists listed in sitemap.xml.
	sitemapSize = 5000
	// publicPageMaxAge lets browsers and proxies reuse a page briefly.
	publicPageMaxAge = "public, max-age=60"
)

// PublicPages serves the public, search-engine-friendly side of rhythmo as
// plain HTML: the most-liked public playlists at /, one public playlist at
// /p/{token}, with sitemap.xml and robots.txt. Visitors need no account;
// link-only and private playlists are never shown.
type PublicPages struct {
	playlists SharedPlaylistStore
	streams   StreamPresigner
	limits    AnonymousLimits
	// contact is the email the privacy page gives for questions and
	// account deletion; the page leaves it out when it is empty.
	contact string
}

func NewPublicPages(playlists SharedPlaylistStore, streams StreamPresigner, limits AnonymousLimits) *PublicPages {
	return &PublicPages{playlists: playlists, streams: streams, limits: limits}
}

func (p *PublicPages) register(mux *http.ServeMux) {
	mux.HandleFunc("GET /{$}", p.handleHome)
	mux.HandleFunc("GET /p/{token}", p.handlePlaylist)
	mux.HandleFunc("GET /p/{token}/t/{trackId}", p.handleTrack)
	mux.HandleFunc("GET /sitemap.xml", p.handleSitemap)
	mux.HandleFunc("GET /robots.txt", p.handleRobots)
	mux.HandleFunc("GET /nafir.png", p.handleIcon)
	mux.HandleFunc("GET /privacy", p.handlePrivacy)
	mux.HandleFunc("GET /delete-account", p.handleDeleteAccount)
}

type pageMeta struct {
	Title       string
	Description string
	Canonical   string
	Image       string
	OGType      string
	NoIndex     bool
	// JSONLD is structured data for search engines; it is JSON-encoded
	// safely by html/template inside its script tag.
	JSONLD any
}

type publicListItem struct {
	ShareToken string
	Name       string
	Owner      string
	TrackCount int
	LikeCount  int
}

type publicTrack struct {
	Title  string
	Artist string
	Stream string
}

type publicPlaylist struct {
	ShareToken string
	Name       string
	Owner      string
	TrackCount int
	LikeCount  int
	Tracks     []publicTrack
}

// origin is the site's own scheme and host, as Caddy forwards them.
func origin(r *http.Request) string {
	scheme := "https"
	if r.TLS == nil && r.Header.Get("X-Forwarded-Proto") != "https" {
		scheme = "http"
	}
	return scheme + "://" + r.Host
}

func (p *PublicPages) render(w http.ResponseWriter, status int, name string, data any) {
	var page bytes.Buffer
	if err := publicTemplates[name].ExecuteTemplate(&page, "layout", data); err != nil {
		internalError(w, "render public page", err)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(status)
	_, _ = page.WriteTo(w)
}

func (p *PublicPages) handleHome(w http.ResponseWriter, r *http.Request) {
	if !enforceRateLimit(w, p.limits.View, clientIP(r)) {
		return
	}
	listed, err := p.playlists.Popular(r.Context(), "", publicListSize)
	if err != nil {
		internalError(w, "list public playlists", err)
		return
	}
	site := origin(r)
	items := make([]publicListItem, 0, len(listed))
	listJSON := make([]map[string]any, 0, len(listed))
	for i, pl := range listed {
		items = append(items, publicListItem{
			ShareToken: pl.ShareToken, Name: pl.Name, Owner: bot.MaskEmail(pl.OwnerEmail),
			TrackCount: pl.TrackCount, LikeCount: pl.Likes.Count,
		})
		listJSON = append(listJSON, map[string]any{
			"@type": "ListItem", "position": i + 1, "url": site + "/p/" + pl.ShareToken, "name": pl.Name,
		})
	}
	w.Header().Set("Cache-Control", publicPageMaxAge)
	p.render(w, http.StatusOK, "home", struct {
		pageMeta
		Playlists []publicListItem
	}{
		pageMeta: pageMeta{
			Title:       "ریتمو — فهرست‌های پخش محبوب",
			Description: "فهرست‌های پخش محبوب کاربران ریتمو را بدون ثبت‌نام بشنو و فهرست پخش خودت را بساز.",
			Canonical:   site + "/", Image: site + "/nafir.png", OGType: "website",
			JSONLD: map[string]any{
				"@context": "https://schema.org", "@type": "ItemList",
				"name": "فهرست‌های پخش محبوب ریتمو", "itemListElement": listJSON,
			},
		},
		Playlists: items,
	})
}

// publicPlaylistFor loads the public playlist at {token}, or writes the
// not-found page: link-only and private playlists look the same as missing.
func (p *PublicPages) publicPlaylistFor(w http.ResponseWriter, r *http.Request) (store.SharedPlaylist, bool) {
	token := r.PathValue("token")
	shared := store.SharedPlaylist{}
	err := store.ErrNotFound
	if validShareToken(token) {
		shared, err = p.playlists.ForShareToken(r.Context(), token)
	}
	if err == nil && !shared.IsPublic {
		err = store.ErrNotFound
	}
	if errors.Is(err, store.ErrNotFound) {
		p.render(w, http.StatusNotFound, "missing", struct{ pageMeta }{pageMeta{
			Title: "پیدا نشد — ریتمو", Description: "این فهرست پخش عمومی نیست یا حذف شده است.",
			Canonical: origin(r) + r.URL.Path, Image: origin(r) + "/nafir.png", OGType: "website", NoIndex: true,
		}})
		return store.SharedPlaylist{}, false
	}
	if err != nil {
		internalError(w, "load public playlist", err)
		return store.SharedPlaylist{}, false
	}
	return shared, true
}

func (p *PublicPages) handlePlaylist(w http.ResponseWriter, r *http.Request) {
	if !enforceRateLimit(w, p.limits.View, clientIP(r)) {
		return
	}
	shared, ok := p.publicPlaylistFor(w, r)
	if !ok {
		return
	}
	likes, err := p.playlists.LikesFor(r.Context(), shared.ID, "")
	if err != nil {
		internalError(w, "load playlist likes", err)
		return
	}
	site := origin(r)
	token := *shared.ShareToken
	page := publicPlaylist{
		ShareToken: token, Name: shared.Name, Owner: bot.MaskEmail(shared.OwnerEmail),
		TrackCount: len(shared.Tracks), LikeCount: likes.Count,
	}
	recordings := make([]map[string]any, 0, len(shared.Tracks))
	var artists []string
	seen := map[string]bool{}
	for _, t := range shared.Tracks {
		artist := ""
		if t.Artist != nil {
			artist = strings.TrimSpace(*t.Artist)
		}
		page.Tracks = append(page.Tracks, publicTrack{
			Title: t.Title, Artist: artist, Stream: "/p/" + token + "/t/" + t.ID,
		})
		recording := map[string]any{"@type": "MusicRecording", "name": t.Title}
		if artist != "" {
			recording["byArtist"] = map[string]any{"@type": "MusicGroup", "name": artist}
			if !seen[strings.ToLower(artist)] && len(artists) < 5 {
				seen[strings.ToLower(artist)] = true
				artists = append(artists, artist)
			}
		}
		recordings = append(recordings, recording)
	}
	description := fmt.Sprintf("فهرست پخش «%s» با %d آهنگ در ریتمو", shared.Name, len(shared.Tracks))
	if len(artists) > 0 {
		description += "، از " + strings.Join(artists, "، ")
	}
	description += ". بدون ثبت‌نام بشنو."
	canonical := site + "/p/" + token
	w.Header().Set("Cache-Control", publicPageMaxAge)
	p.render(w, http.StatusOK, "playlist", struct {
		pageMeta
		Playlist publicPlaylist
	}{
		pageMeta: pageMeta{
			Title:       shared.Name + " — فهرست پخش در ریتمو",
			Description: description,
			Canonical:   canonical, Image: site + "/nafir.png", OGType: "music.playlist",
			JSONLD: map[string]any{
				"@context": "https://schema.org", "@type": "MusicPlaylist",
				"name": shared.Name, "url": canonical, "numTracks": len(shared.Tracks), "track": recordings,
			},
		},
		Playlist: page,
	})
}

// handleTrack sends a player to a short-lived URL for one track of a public
// playlist, so the page itself never holds an expiring link.
func (p *PublicPages) handleTrack(w http.ResponseWriter, r *http.Request) {
	if !enforceRateLimit(w, p.limits.Stream, clientIP(r)) {
		return
	}
	token := r.PathValue("token")
	if !validShareToken(token) {
		http.NotFound(w, r)
		return
	}
	track, err := p.playlists.SharedTrack(r.Context(), token, r.PathValue("trackId"), true)
	if errors.Is(err, store.ErrNotFound) {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		internalError(w, "load public track", err)
		return
	}
	url, _, err := p.streams.PresignGet(r.Context(), track.StorageKey)
	if err != nil {
		internalError(w, "presign public track", err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	http.Redirect(w, r, url, http.StatusFound)
}

type sitemapURL struct {
	Loc     string `xml:"loc"`
	LastMod string `xml:"lastmod,omitempty"`
}

type sitemap struct {
	XMLName xml.Name     `xml:"urlset"`
	XMLNS   string       `xml:"xmlns,attr"`
	URLs    []sitemapURL `xml:"url"`
}

func (p *PublicPages) handleSitemap(w http.ResponseWriter, r *http.Request) {
	listed, err := p.playlists.Popular(r.Context(), "", sitemapSize)
	if err != nil {
		internalError(w, "list sitemap playlists", err)
		return
	}
	site := origin(r)
	urls := []sitemapURL{{Loc: site + "/"}}
	for _, pl := range listed {
		urls = append(urls, sitemapURL{
			Loc: site + "/p/" + pl.ShareToken, LastMod: pl.UpdatedAt.UTC().Format(time.DateOnly),
		})
	}
	body, err := xml.MarshalIndent(sitemap{XMLNS: "http://www.sitemaps.org/schemas/sitemap/0.9", URLs: urls}, "", "  ")
	if err != nil {
		internalError(w, "encode sitemap", err)
		return
	}
	w.Header().Set("Content-Type", "application/xml; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=3600")
	_, _ = w.Write([]byte(xml.Header))
	_, _ = w.Write(body)
}

func (p *PublicPages) handleRobots(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=3600")
	fmt.Fprintf(w, "User-agent: *\nAllow: /\nDisallow: /app/\nDisallow: /api/\nSitemap: %s/sitemap.xml\n", origin(r))
}

// WithContact sets the email the privacy page gives for questions and
// account deletion.
func (p *PublicPages) WithContact(email string) *PublicPages {
	p.contact = strings.TrimSpace(email)
	return p
}

// privacyUpdated is when the privacy policy text last changed.
const privacyUpdated = "۱۰ مهر ۱۴۰۵"

// handlePrivacy serves the privacy policy app stores link to.
func (p *PublicPages) handlePrivacy(w http.ResponseWriter, r *http.Request) {
	site := origin(r)
	w.Header().Set("Cache-Control", "public, max-age=3600")
	p.render(w, http.StatusOK, "privacy", struct {
		pageMeta
		Updated string
		Contact string
	}{
		pageMeta: pageMeta{
			Title:       "حریم خصوصی — ریتمو",
			Description: "ریتمو چه اطلاعاتی نگه می‌دارد، چه کسی آن را می‌بیند و چطور حذفش کنی.",
			Canonical:   site + "/privacy", Image: site + "/nafir.png", OGType: "website",
		},
		Updated: privacyUpdated,
		Contact: p.contact,
	})
}

// deleteAccountUpdated is when the account deletion page last changed.
const deleteAccountUpdated = "۱۰ مهر ۱۴۰۵"

// handleDeleteAccount serves the account deletion page app stores link to,
// for people who no longer have the app.
func (p *PublicPages) handleDeleteAccount(w http.ResponseWriter, r *http.Request) {
	site := origin(r)
	w.Header().Set("Cache-Control", "public, max-age=3600")
	p.render(w, http.StatusOK, "delete", struct {
		pageMeta
		Updated string
		Contact string
	}{
		pageMeta: pageMeta{
			Title:       "حذف حساب کاربری — ریتمو",
			Description: "چطور حساب ریتمو و همه‌ی موسیقی‌ها و فهرست‌های پخشت را برای همیشه حذف کنی.",
			Canonical:   site + "/delete-account", Image: site + "/nafir.png", OGType: "website",
		},
		Updated: deleteAccountUpdated,
		Contact: p.contact,
	})
}

func (p *PublicPages) handleIcon(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "public, max-age=86400")
	http.ServeFileFS(w, r, publicFiles, "public/nafir.png")
}
