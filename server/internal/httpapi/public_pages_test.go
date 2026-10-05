package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/store"
)

func publicSite(data *sharingStore, limits AnonymousLimits) http.Handler {
	return NewHandler(Config{Public: NewPublicPages(data, fixedPresigner{}, limits)})
}

func get(handler http.Handler, path string) *httptest.ResponseRecorder {
	request := httptest.NewRequest(http.MethodGet, path, nil)
	request.Host = "nafir.example.com"
	request.Header.Set("X-Forwarded-Proto", "https")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	return response
}

// jsonLD returns the page's structured data, failing if it isn't valid JSON.
func jsonLD(t *testing.T, page string) map[string]any {
	t.Helper()
	match := regexp.MustCompile(`(?s)<script type="application/ld\+json">(.*?)</script>`).FindStringSubmatch(page)
	if match == nil {
		t.Fatal("no JSON-LD on the page")
	}
	var data map[string]any
	if err := json.Unmarshal([]byte(match[1]), &data); err != nil {
		t.Fatalf("JSON-LD is not JSON: %v\n%s", err, match[1])
	}
	return data
}

func TestPublicFrontPageListsPublicPlaylists(t *testing.T) {
	token := strings.Repeat("A", 22)
	evil := `</script><script>alert(1)</script>`
	data := &sharingStore{token: &token, public: true, name: evil, tracks: []store.Track{{ID: "t1", Title: "song"}}}
	site := publicSite(data, AnonymousLimits{})

	response := get(site, "/")
	page := response.Body.String()
	if response.Code != http.StatusOK || !strings.HasPrefix(response.Header().Get("Content-Type"), "text/html") {
		t.Fatalf("front page = %d %s", response.Code, response.Header().Get("Content-Type"))
	}
	for _, want := range []string{
		`<html lang="fa" dir="rtl">`,
		`<link rel="canonical" href="https://nafir.example.com/">`,
		`<meta property="og:title"`,
		`href="/p/` + token + `"`,
		`<bdi>a***@example.com</bdi> · 1 آهنگ`,
		`href="/app/"`,
	} {
		if !strings.Contains(page, want) {
			t.Errorf("front page is missing %q", want)
		}
	}
	if strings.Contains(page, "<script>alert(1)") {
		t.Fatal("a playlist name was not escaped")
	}
	if list := jsonLD(t, page); list["@type"] != "ItemList" {
		t.Fatalf("JSON-LD = %v", list)
	}
	if response.Header().Get("Cache-Control") != publicPageMaxAge {
		t.Fatalf("cache = %q", response.Header().Get("Cache-Control"))
	}

	data.public = false
	if page := get(site, "/").Body.String(); strings.Contains(page, token) {
		t.Fatal("a link-only playlist was listed")
	}
}

func TestPublicPlaylistPage(t *testing.T) {
	token := strings.Repeat("A", 22)
	artist := `"><img src=x onerror=alert(1)>`
	data := &sharingStore{token: &token, public: true, name: "Road trip", tracks: []store.Track{
		{ID: "t1", Title: "First", Artist: &artist, StorageKey: "users/alice/tracks/t1/a.mp3"},
		{ID: "t2", Title: "Second", StorageKey: "users/alice/tracks/t2/b.mp3"},
	}}
	site := publicSite(data, AnonymousLimits{})

	response := get(site, "/p/"+token)
	page := response.Body.String()
	if response.Code != http.StatusOK {
		t.Fatalf("playlist page = %d", response.Code)
	}
	for _, want := range []string{
		`<title>Road trip — فهرست پخش در نفیر</title>`,
		`<meta name="description" content="فهرست پخش «Road trip» با 2 آهنگ در نفیر`,
		`<link rel="canonical" href="https://nafir.example.com/p/` + token + `">`,
		`<meta property="og:type" content="music.playlist">`,
		`src="/p/` + token + `/t/t1"`,
		`href="/app/?shared=` + token + `"`,
	} {
		if !strings.Contains(page, want) {
			t.Errorf("playlist page is missing %q", want)
		}
	}
	if strings.Contains(page, "<img src=x") || strings.Contains(page, "users/alice") {
		t.Fatal("user text was not escaped, or a storage key leaked")
	}
	if ld := jsonLD(t, page); ld["@type"] != "MusicPlaylist" || ld["numTracks"] != float64(2) {
		t.Fatalf("JSON-LD = %v", ld)
	}

	// The track link sends the player to a short-lived URL.
	track := get(site, "/p/"+token+"/t/t1")
	if track.Code != http.StatusFound || !strings.Contains(track.Header().Get("Location"), "users/alice/tracks/t1/") {
		t.Fatalf("track = %d %s", track.Code, track.Header().Get("Location"))
	}
	if get(site, "/p/"+token+"/t/elsewhere").Code != http.StatusNotFound {
		t.Fatal("a track outside the playlist played")
	}

	// Link-only, malformed and unknown are all the same unindexed 404.
	data.public = false
	for _, path := range []string{"/p/" + token, "/p/not-a-token", "/p/" + strings.Repeat("B", 22)} {
		response := get(site, path)
		if response.Code != http.StatusNotFound || !strings.Contains(response.Body.String(), `<meta name="robots" content="noindex">`) {
			t.Errorf("%s = %d", path, response.Code)
		}
	}
	if get(site, "/p/"+token+"/t/t1").Code != http.StatusNotFound {
		t.Fatal("a link-only playlist's track played")
	}
}

func TestPublicPagesAreRateLimitedPerIP(t *testing.T) {
	token := strings.Repeat("A", 22)
	data := &sharingStore{token: &token, public: true, tracks: []store.Track{{ID: "t1", StorageKey: "k"}}}
	site := publicSite(data, AnonymousLimits{
		View:   NewRateLimiter(RateLimit{Requests: 2, Window: time.Hour}, 10),
		Stream: NewRateLimiter(RateLimit{Requests: 1, Window: time.Hour}, 10),
	})
	get(site, "/")
	get(site, "/p/"+token)
	if response := get(site, "/"); response.Code != http.StatusTooManyRequests || response.Header().Get("Retry-After") == "" {
		t.Fatalf("third page = %d", response.Code)
	}
	get(site, "/p/"+token+"/t/t1")
	if response := get(site, "/p/"+token+"/t/t1"); response.Code != http.StatusTooManyRequests {
		t.Fatalf("second track = %d", response.Code)
	}
}

func TestSitemapAndRobots(t *testing.T) {
	token := strings.Repeat("A", 22)
	data := &sharingStore{token: &token, public: true}
	site := publicSite(data, AnonymousLimits{})

	sitemap := get(site, "/sitemap.xml").Body.String()
	for _, want := range []string{
		`<?xml version="1.0" encoding="UTF-8"?>`,
		`<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">`,
		`<loc>https://nafir.example.com/</loc>`,
		`<loc>https://nafir.example.com/p/` + token + `</loc>`,
	} {
		if !strings.Contains(sitemap, want) {
			t.Errorf("sitemap is missing %q:\n%s", want, sitemap)
		}
	}
	robots := get(site, "/robots.txt").Body.String()
	if !strings.Contains(robots, "Disallow: /app/") || !strings.Contains(robots, "Sitemap: https://nafir.example.com/sitemap.xml") {
		t.Fatalf("robots.txt = %s", robots)
	}
	if icon := get(site, "/nafir.png"); icon.Code != http.StatusOK || icon.Header().Get("Content-Type") != "image/png" {
		t.Fatalf("icon = %d %s", icon.Code, icon.Header().Get("Content-Type"))
	}
	// Only the exact root is the front page; other paths stay 404.
	if get(site, "/elsewhere").Code != http.StatusNotFound {
		t.Fatal("unknown paths should not render the front page")
	}
}

func TestPrivacyPage(t *testing.T) {
	data := &sharingStore{}
	page := func(pages *PublicPages) string {
		t.Helper()
		response := get(NewHandler(Config{Public: pages}), "/privacy")
		if response.Code != http.StatusOK || !strings.HasPrefix(response.Header().Get("Content-Type"), "text/html") {
			t.Fatalf("privacy = %d %q", response.Code, response.Header().Get("Content-Type"))
		}
		return response.Body.String()
	}

	body := page(NewPublicPages(data, fixedPresigner{}, AnonymousLimits{}).WithContact("privacy@example.com"))
	for _, want := range []string{"حریم خصوصی نفیر", "bcrypt", `href="mailto:privacy@example.com"`, `<link rel="canonical" href="https://nafir.example.com/privacy">`} {
		if !strings.Contains(body, want) {
			t.Fatalf("privacy page lacks %q", want)
		}
	}
	// Every public page links to it from the footer.
	if !strings.Contains(body, `<a href="/privacy">حریم خصوصی</a>`) {
		t.Fatal("footer has no privacy link")
	}
	// Without a contact the page still works and links nowhere.
	if body := page(NewPublicPages(data, fixedPresigner{}, AnonymousLimits{})); strings.Contains(body, "mailto:") {
		t.Fatal("privacy page links an empty contact")
	}
}

func TestDeleteAccountPage(t *testing.T) {
	data := &sharingStore{}
	page := func(pages *PublicPages) string {
		t.Helper()
		response := get(NewHandler(Config{Public: pages}), "/delete-account")
		if response.Code != http.StatusOK || !strings.HasPrefix(response.Header().Get("Content-Type"), "text/html") {
			t.Fatalf("delete-account = %d %q", response.Code, response.Header().Get("Content-Type"))
		}
		return response.Body.String()
	}

	body := page(NewPublicPages(data, fixedPresigner{}, AnonymousLimits{}).WithContact("privacy@example.com"))
	for _, want := range []string{
		"حذف حساب کاربری نفیر",
		"تنظیمات",
		`href="mailto:privacy@example.com?subject=%D8%AD%D8%B0%D9%81%20%D8%AD%D8%B3%D8%A7%D8%A8%20%D9%86%D9%81%DB%8C%D8%B1"`,
		`<link rel="canonical" href="https://nafir.example.com/delete-account">`,
		`<a href="/privacy">`,
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("delete-account page lacks %q", want)
		}
	}
	if body := page(NewPublicPages(data, fixedPresigner{}, AnonymousLimits{})); strings.Contains(body, "mailto:") {
		t.Fatal("delete-account page links an empty contact")
	}

	// The privacy policy explains in-app deletion and links here, and every
	// page's footer does too.
	privacy := get(NewHandler(Config{Public: NewPublicPages(data, fixedPresigner{}, AnonymousLimits{})}), "/privacy").Body.String()
	for _, want := range []string{"حذف حساب کاربری</strong>", `<a href="/delete-account">صفحه‌ی حذف حساب کاربری</a>`, `<a href="/delete-account">حذف حساب</a>`} {
		if !strings.Contains(privacy, want) {
			t.Fatalf("privacy page lacks %q", want)
		}
	}
}
