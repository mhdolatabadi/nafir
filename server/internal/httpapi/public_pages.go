package httpapi

import (
	"bytes"
	"embed"
	"encoding/xml"
	"errors"
	"fmt"
	"html/template"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/bot"
	"github.com/mhdolatabadi/nafir/server/internal/display"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

//go:embed public/*.html public/nafir.png public/social.png
var publicFiles embed.FS

var publicTemplates = map[string]*template.Template{
	"home":     template.Must(template.New("layout.html").Funcs(template.FuncMap{"digits": display.PersianDigits}).ParseFS(publicFiles, "public/layout.html", "public/home.html")),
	"playlist": template.Must(template.New("layout.html").Funcs(template.FuncMap{"digits": display.PersianDigits}).ParseFS(publicFiles, "public/layout.html", "public/playlist.html")),
	"missing":  template.Must(template.New("layout.html").Funcs(template.FuncMap{"digits": display.PersianDigits}).ParseFS(publicFiles, "public/layout.html", "public/missing.html")),
	"privacy":  template.Must(template.New("layout.html").Funcs(template.FuncMap{"digits": display.PersianDigits}).ParseFS(publicFiles, "public/layout.html", "public/privacy.html")),
	"delete":   template.Must(template.New("layout.html").Funcs(template.FuncMap{"digits": display.PersianDigits}).ParseFS(publicFiles, "public/layout.html", "public/delete_account.html")),
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
	// quotaBytes is each account's cloud storage, as the front page tells it.
	quotaBytes int64
	// androidApp is where the Android app is installed from; the front page
	// offers it only when set.
	androidApp string
	// contact is the email the privacy page gives for questions and
	// account deletion; the page leaves it out when it is empty.
	contact string
	// site is the configured origin every canonical, Open Graph and sitemap
	// URL uses, so one page never shows up under several hosts; empty
	// falls back to the request's own host.
	site string
	// verify holds the search console ownership tokens for the front page.
	verify siteVerification
}

// siteVerification is the content of the search engines' ownership <meta>
// tags; an empty one is left out.
type siteVerification struct {
	Google string
	Bing   string
}

func NewPublicPages(playlists SharedPlaylistStore, streams StreamPresigner, limits AnonymousLimits) *PublicPages {
	return &PublicPages{playlists: playlists, streams: streams, limits: limits, quotaBytes: 1 << 30}
}

// WithQuota sets the per-account storage the front page mentions.
func (p *PublicPages) WithQuota(bytes int64) *PublicPages {
	if bytes > 0 {
		p.quotaBytes = bytes
	}
	return p
}

// WithAndroidApp sets the https link the Android app is installed from,
// such as its store page; anything else is ignored.
func (p *PublicPages) WithAndroidApp(link string) *PublicPages {
	link = strings.TrimSpace(link)
	if u, err := url.Parse(link); err == nil && u.Scheme == "https" && u.Host != "" && u.User == nil {
		p.androidApp = link
	} else {
		p.androidApp = ""
	}
	return p
}

// quotaText says bytes in Persian, in whole gigabytes or megabytes.
func quotaText(bytes int64) string {
	if bytes >= 1<<30 && bytes%(1<<30) == 0 {
		return display.PersianDigits(bytes>>30) + " گیگابایت"
	}
	return display.PersianDigits((bytes+(1<<20)-1)>>20) + " مگابایت"
}

// publicFeature is one point of what rhythmo does, on the front page.
type publicFeature struct {
	Title string
	Text  string
}

// publicQuestion is one frequently asked question, shown on the front page
// and given to search engines as FAQ structured data.
type publicQuestion struct {
	Question string
	Answer   string
}

var publicFeatures = []publicFeature{
	{"کتابخانه‌ی ابری با کیفیت اصلی", "آهنگ‌هایت را آپلود کن؛ همان فایلی که فرستادی نگه داشته و پخش می‌شود، بدون فشرده‌سازی دوباره."},
	{"فهرست پخش و اشتراک‌گذاری", "فهرست پخش بساز، با لینک یا به‌صورت عمومی به اشتراک بگذار، یا با دوستانت فهرست مشترک بساز."},
	{"وب و اندروید", "در مرورگر بدون نصب گوش بده؛ در اندروید موسیقی خود گوشی را هم ببین و آهنگ‌ها را برای پخش بدون اینترنت دانلود کن."},
	{"مشخصات درست برای هر آهنگ", "نام، خواننده و آلبوم را ویرایش کن؛ فایلی که دانلود می‌کنی همان مشخصات و نام را دارد."},
	{"افزودن از لینک و بات", "آهنگ را با لینک یا از طریق بات‌های بله و تلگرام مستقیم به کتابخانه‌ات بفرست."},
}

func (p *PublicPages) questions() []publicQuestion {
	return []publicQuestion{
		{"ریتمو رایگان است؟", "بله. هر حساب " + quotaText(p.quotaBytes) + " فضای ابری برای موسیقی دارد."},
		{"چه قالب‌هایی را می‌شود آپلود کرد؟", "MP3، M4A، AAC، FLAC، OGG، Opus، WAV و WebM."},
		{"کیفیت آهنگ‌ها کم می‌شود؟", "نه. ریتمو فایل را همان‌طور که آپلود کرده‌ای نگه می‌دارد و پخش می‌کند."},
		{"چه کسی فهرست‌های پخش مرا می‌بیند؟", "فقط خودت، مگر اینکه لینکش را بسازی. فهرستی که «عمومی» کنی در صفحه‌ی اول ریتمو هم نشان داده می‌شود."},
		{"اپ اندروید هم دارد؟", "بله. ریتمو روی وب بدون نصب کار می‌کند و اپ اندروید هم دارد که موسیقی گوشی را هم نشان می‌دهد و پخش بدون اینترنت دارد."},
		{"چطور حسابم را حذف کنم؟", "از تنظیمات اپ، «حذف حساب کاربری» را بزن. همه‌ی آهنگ‌ها و فهرست‌های پخشت برای همیشه پاک می‌شوند."},
	}
}

func (p *PublicPages) register(mux *http.ServeMux) {
	mux.HandleFunc("GET /{$}", p.handleHome)
	mux.HandleFunc("GET /p/{token}", p.handlePlaylist)
	mux.HandleFunc("GET /p/{token}/t/{trackId}", p.handleTrack)
	mux.HandleFunc("GET /sitemap.xml", p.handleSitemap)
	mux.HandleFunc("GET /robots.txt", p.handleRobots)
	mux.HandleFunc("GET /nafir.png", p.handleIcon)
	mux.HandleFunc("GET /social.png", p.handleSocialImage)
	mux.HandleFunc("GET /privacy", p.handlePrivacy)
	mux.HandleFunc("GET /delete-account", p.handleDeleteAccount)
	mux.HandleFunc("GET /", p.handleNotFound)
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

// WithSite sets the origin, such as https://rhythmo.ir, that canonical,
// Open Graph and sitemap URLs use. Anything but a plain http(s) origin is
// ignored, and the request's host is used instead.
func (p *PublicPages) WithSite(site string) *PublicPages {
	u, err := url.Parse(strings.TrimRight(strings.TrimSpace(site), "/"))
	if err != nil || (u.Scheme != "https" && u.Scheme != "http") || u.Host == "" ||
		u.Path != "" || u.RawQuery != "" || u.Fragment != "" || u.User != nil {
		p.site = ""
		return p
	}
	p.site = u.Scheme + "://" + u.Host
	return p
}

// WithVerification sets the Google Search Console and Bing Webmaster Tools
// ownership tokens shown on the front page; empty ones are left out.
func (p *PublicPages) WithVerification(google, bing string) *PublicPages {
	p.verify = siteVerification{Google: strings.TrimSpace(google), Bing: strings.TrimSpace(bing)}
	return p
}

// origin is the configured site origin, or the request's own scheme and
// host when none is set.
func (p *PublicPages) origin(r *http.Request) string {
	if p.site != "" {
		return p.site
	}
	return origin(r)
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
	site := p.origin(r)
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
	questions := p.questions()
	faqJSON := make([]map[string]any, 0, len(questions))
	for _, q := range questions {
		faqJSON = append(faqJSON, map[string]any{
			"@type": "Question", "name": q.Question,
			"acceptedAnswer": map[string]any{"@type": "Answer", "text": q.Answer},
		})
	}
	w.Header().Set("Cache-Control", publicPageMaxAge)
	p.render(w, http.StatusOK, "home", struct {
		pageMeta
		Verify     siteVerification
		Features   []publicFeature
		Questions  []publicQuestion
		AndroidApp string
		Playlists  []publicListItem
	}{
		Verify: p.verify,
		pageMeta: pageMeta{
			Title: "ریتمو — پخش‌کننده و فضای ابری موسیقی",
			Description: "ریتمو کتابخانه‌ی موسیقی ابری توست: آهنگ‌هایت را با کیفیت اصلی آپلود کن، " +
				"فهرست پخش بساز و روی وب و اندروید گوش بده. فهرست‌های پخش محبوب را بدون ثبت‌نام بشنو.",
			Canonical: site + "/", Image: site + "/social.png", OGType: "website",
			JSONLD: map[string]any{
				"@context": "https://schema.org",
				"@graph": []map[string]any{
					{"@type": "WebSite", "@id": site + "/#website", "name": "ریتمو", "alternateName": "rhythmo",
						"url": site + "/", "inLanguage": "fa"},
					{"@type": "Organization", "@id": site + "/#organization", "name": "ریتمو", "url": site + "/",
						"logo": site + "/nafir.png"},
					{"@type": "ItemList", "name": "فهرست‌های پخش محبوب ریتمو", "itemListElement": listJSON},
					{"@type": "FAQPage", "mainEntity": faqJSON},
				},
			},
		},
		Features: publicFeatures, Questions: questions, AndroidApp: p.androidApp,
		Playlists: items,
	})
}

// renderMissing writes the branded not-found page, which search engines
// are told not to index.
func (p *PublicPages) renderMissing(w http.ResponseWriter, r *http.Request, heading, body, description string) {
	site := p.origin(r)
	p.render(w, http.StatusNotFound, "missing", struct {
		pageMeta
		Heading string
		Body    string
	}{
		pageMeta: pageMeta{
			Title: "پیدا نشد — ریتمو", Description: description,
			Canonical: site + r.URL.Path, Image: site + "/social.png", OGType: "website", NoIndex: true,
		},
		Heading: heading, Body: body,
	})
}

// handleNotFound answers every path nothing else serves: API clients get
// the usual JSON error, people and crawlers the branded page.
func (p *PublicPages) handleNotFound(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/api" || strings.HasPrefix(r.URL.Path, "/api/") {
		writeError(w, http.StatusNotFound, "not_found")
		return
	}
	p.renderMissing(w, r, "این صفحه پیدا نشد",
		"نشانی را بررسی کن یا از صفحه‌ی اول ادامه بده.",
		"صفحه‌ای که دنبالش بودی در ریتمو پیدا نشد.")
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
		p.renderMissing(w, r, "این فهرست پخش پیدا نشد",
			"ممکن است صاحبش آن را خصوصی کرده یا حذف کرده باشد.",
			"این فهرست پخش عمومی نیست یا حذف شده است.")
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
	site := p.origin(r)
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
	description := fmt.Sprintf("فهرست پخش «%s» با %s آهنگ در ریتمو", shared.Name, display.PersianDigits(len(shared.Tracks)))
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
			Canonical:   canonical, Image: site + "/social.png", OGType: "music.playlist",
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
	site := p.origin(r)
	urls := []sitemapURL{{Loc: site + "/"}, {Loc: site + "/privacy"}, {Loc: site + "/delete-account"}}
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
	fmt.Fprintf(w, "User-agent: *\nAllow: /\nDisallow: /app/\nDisallow: /api/\nSitemap: %s/sitemap.xml\n", p.origin(r))
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
	site := p.origin(r)
	w.Header().Set("Cache-Control", "public, max-age=3600")
	p.render(w, http.StatusOK, "privacy", struct {
		pageMeta
		Updated string
		Contact string
	}{
		pageMeta: pageMeta{
			Title:       "حریم خصوصی — ریتمو",
			Description: "ریتمو چه اطلاعاتی نگه می‌دارد، چه کسی آن را می‌بیند و چطور حذفش کنی.",
			Canonical:   site + "/privacy", Image: site + "/social.png", OGType: "website",
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
	site := p.origin(r)
	w.Header().Set("Cache-Control", "public, max-age=3600")
	p.render(w, http.StatusOK, "delete", struct {
		pageMeta
		Updated string
		Contact string
	}{
		pageMeta: pageMeta{
			Title:       "حذف حساب کاربری — ریتمو",
			Description: "چطور حساب ریتمو و همه‌ی موسیقی‌ها و فهرست‌های پخشت را برای همیشه حذف کنی.",
			Canonical:   site + "/delete-account", Image: site + "/social.png", OGType: "website",
		},
		Updated: deleteAccountUpdated,
		Contact: p.contact,
	})
}

// handleSocialImage serves the 1200×630 card link previews show.
func (p *PublicPages) handleSocialImage(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "public, max-age=604800")
	http.ServeFileFS(w, r, publicFiles, "public/social.png")
}

func (p *PublicPages) handleIcon(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "public, max-age=86400")
	http.ServeFileFS(w, r, publicFiles, "public/nafir.png")
}
