package linkimport

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/bot"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

// testFetcher may reach the test servers on loopback, on their ports only.
func testFetcher(servers ...*httptest.Server) *Fetcher {
	ports := map[uint16]bool{}
	for _, s := range servers {
		u, _ := url.Parse(s.URL)
		p, _ := strconv.Atoi(u.Port())
		ports[uint16(p)] = true
	}
	return newFetcher(func(ip netip.Addr) bool { return ip.IsLoopback() }, ports)
}

func mustParse(t *testing.T, raw string) *url.URL {
	t.Helper()
	u, err := ParseURL(raw)
	if err != nil {
		t.Fatal(err)
	}
	return u
}

var mp3 = append([]byte("ID3\x04\x00\x00\x00\x00\x00\x00"), bytes.Repeat([]byte{0}, 200)...)

func TestPublicAddress(t *testing.T) {
	for _, tc := range []struct {
		ip   string
		want bool
	}{
		{"8.8.8.8", true},
		{"2001:4860:4860::8888", true},
		{"127.0.0.1", false},
		{"::1", false},
		{"10.1.2.3", false},
		{"172.16.0.1", false},
		{"192.168.1.1", false},
		{"169.254.169.254", false}, // cloud metadata
		{"100.64.0.1", false},
		{"0.0.0.0", false},
		{"224.0.0.1", false},
		{"fc00::1", false},
		{"fe80::1", false},
		{"::ffff:127.0.0.1", false},
		{"::ffff:10.0.0.1", false},
		{"64:ff9b::a00:1", false},
		{"2002:a00:1::", false},
	} {
		if got := PublicAddress(netip.MustParseAddr(tc.ip)); got != tc.want {
			t.Errorf("PublicAddress(%s) = %v", tc.ip, got)
		}
	}
}

func TestParseURL(t *testing.T) {
	for _, raw := range []string{"", "ftp://x.com/a.mp3", "file:///etc/passwd", "javascript:alert(1)",
		"https://user:pass@x.com/a.mp3", "//x.com/a.mp3", "https:///a.mp3", "https://x.com/" + strings.Repeat("a", 3000)} {
		if _, err := ParseURL(raw); !errors.Is(err, ErrInvalidURL) {
			t.Errorf("ParseURL(%q) = %v", raw, err)
		}
	}
	if _, err := ParseURL("  https://music.example.ir/song/1  "); err != nil {
		t.Fatal(err)
	}
}

func TestFetcherRefusesInternalAddresses(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "audio/mpeg")
		w.Write(mp3)
	}))
	defer server.Close()
	// The real fetcher never reaches loopback, by IP or by a name.
	for _, raw := range []string{server.URL + "/a.mp3", strings.Replace(server.URL, "127.0.0.1", "localhost", 1) + "/a.mp3"} {
		if _, err := NewFetcher().Resolve(context.Background(), mustParse(t, raw)); !errors.Is(err, ErrBlocked) {
			t.Fatalf("%s: %v", raw, err)
		}
	}

	// Nor through a redirect to an address it may not reach.
	internal := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("the internal server was reached")
	}))
	defer internal.Close()
	public := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, internal.URL+"/secret.mp3", http.StatusFound)
	}))
	defer public.Close()
	if _, err := testFetcher(public).Resolve(context.Background(), mustParse(t, public.URL+"/song")); !errors.Is(err, ErrBlocked) {
		t.Fatalf("redirect to an internal address: %v", err)
	}
	// Or to another scheme.
	sneaky := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "file:///etc/passwd", http.StatusFound)
	}))
	defer sneaky.Close()
	if _, err := testFetcher(sneaky).Resolve(context.Background(), mustParse(t, sneaky.URL+"/x")); err == nil {
		t.Fatal("followed a redirect to file://")
	}
}

func TestResolveFindsTheBestQualityLink(t *testing.T) {
	var server *httptest.Server
	server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/song":
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			fmt.Fprint(w, `<html><head><meta property="og:audio" content="/media/preview-64.mp3"></head><body>
				<a href="/about">درباره</a>
				<a href="https://cdn.example.com/cover.jpg">کاور</a>
				<a href="/dl/Artist%20-%20Song%20128.mp3">دانلود با کیفیت 128</a>
				<a href="dl/Artist - Song.mp3">دانلود با کیفیت 320</a>
				<audio src="/stream/song.m4a"></audio>
			</body></html>`)
		case "/lossless":
			w.Header().Set("Content-Type", "text/html")
			fmt.Fprint(w, `<a href="/a-320.mp3">320</a><a href="/a.flac">FLAC</a>`)
		case "/empty":
			w.Header().Set("Content-Type", "text/html")
			fmt.Fprint(w, `<p>no music here</p><a href="/x.zip">zip</a>`)
		case "/file":
			w.Header().Set("Content-Type", "audio/mpeg")
			w.Header().Set("Content-Length", strconv.Itoa(len(mp3)))
			w.Write(mp3)
		case "/doc":
			w.Header().Set("Content-Type", "application/pdf")
			fmt.Fprint(w, "%PDF")
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()
	f := testFetcher(server)
	ctx := context.Background()

	got, err := f.Resolve(ctx, mustParse(t, server.URL+"/song"))
	if err != nil || got.URL.String() != server.URL+"/dl/Artist%20-%20Song.mp3" || got.FileName != "Artist - Song.mp3" {
		t.Fatalf("song page = %+v, %v", got, err)
	}
	if got, _ := f.Resolve(ctx, mustParse(t, server.URL+"/lossless")); got.FileName != "a.flac" {
		t.Fatalf("lossless = %+v", got)
	}
	if got, err := f.ResolveAll(ctx, mustParse(t, server.URL+"/song")); err != nil {
		t.Fatalf("resolve all: %v", err)
	} else if len(got) != 3 ||
		got[0].URL.String() != server.URL+"/media/preview-64.mp3" ||
		got[1].URL.String() != server.URL+"/dl/Artist%20-%20Song%20128.mp3" ||
		got[2].URL.String() != server.URL+"/dl/Artist%20-%20Song.mp3" {
		t.Fatalf("resolve all = %+v", got)
	}
	if _, err := f.Resolve(ctx, mustParse(t, server.URL+"/empty")); !errors.Is(err, ErrNoAudio) {
		t.Fatalf("page without audio: %v", err)
	}
	// A link to the file itself, named by its type when the path has no extension.
	if got, err := f.Resolve(ctx, mustParse(t, server.URL+"/file")); err != nil || got.FileName != "file.mp3" || got.SizeBytes != int64(len(mp3)) {
		t.Fatalf("direct file = %+v, %v", got, err)
	}
	if _, err := f.Resolve(ctx, mustParse(t, server.URL+"/doc")); !errors.Is(err, ErrUnsupported) {
		t.Fatalf("pdf: %v", err)
	}
	if _, err := f.Resolve(ctx, mustParse(t, server.URL+"/missing")); !errors.Is(err, ErrUnreachable) {
		t.Fatalf("404: %v", err)
	}
	// Errors are logged, so they never carry the link.
	server.Close()
	if _, err := f.Resolve(ctx, mustParse(t, server.URL+"/song?token=secret")); !errors.Is(err, ErrUnreachable) || strings.Contains(err.Error(), "secret") {
		t.Fatalf("closed server: %v", err)
	}
}

func TestProviderOpen(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/sized.mp3":
			w.Header().Set("Content-Length", strconv.Itoa(len(mp3)))
			w.Write(mp3)
		case "/chunked.mp3":
			// Flushing before the end makes the response chunked, without a length.
			w.Write(mp3[:10])
			w.(http.Flusher).Flush()
			w.Write(mp3[10:])
		case "/huge.mp3":
			w.Write(mp3[:10])
			w.(http.Flusher).Flush()
			w.Write(bytes.Repeat([]byte{0}, 5000))
		}
	}))
	defer server.Close()
	p := NewProvider(testFetcher(server), 1000)
	ctx := context.Background()

	body, size, err := p.Open(ctx, server.URL+"/sized.mp3")
	if err != nil || size != int64(len(mp3)) {
		t.Fatalf("sized = %d, %v", size, err)
	}
	body.Close()

	body, size, err = p.Open(ctx, server.URL+"/chunked.mp3")
	if err != nil || size != int64(len(mp3)) {
		t.Fatalf("chunked = %d, %v", size, err)
	}
	spooled := body.(*tempFile).Name()
	if data, _ := io.ReadAll(body); !bytes.Equal(data, mp3) {
		t.Fatal("spooled bytes differ")
	}
	body.Close()
	if _, err := os.Stat(spooled); !os.IsNotExist(err) {
		t.Fatalf("temporary file left behind: %v", err)
	}

	if _, _, err := p.Open(ctx, server.URL+"/huge.mp3"); !errors.Is(err, bot.ErrFileTooLarge) {
		t.Fatalf("huge: %v", err)
	}
}

// memoryImports is the import queue, in memory.
type memoryImports struct {
	mu      sync.Mutex
	imports map[string]*store.BotImport
	active  int
}

func (m *memoryImports) AddImport(_ context.Context, i store.BotImport) (store.BotImport, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	i.ID = fmt.Sprintf("import-%d", len(m.imports)+1)
	i.State = store.ImportQueued
	i.CreatedAt = time.Now()
	m.imports[i.ID] = &i
	return i, nil
}
func (m *memoryImports) ActiveImports(context.Context, string) (int, error) { return m.active, nil }
func (m *memoryImports) ActiveImportFor(_ context.Context, _, _, fileID string) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, i := range m.imports {
		if i.FileID == fileID && (i.State == store.ImportQueued || i.State == store.ImportDownloading) {
			return true, nil
		}
	}
	return false, nil
}
func (m *memoryImports) RecentImports(context.Context, string, string, int) ([]store.BotImport, error) {
	return nil, nil
}
func (m *memoryImports) StartImport(_ context.Context, id string, _ time.Time) (store.BotImport, bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	i := m.imports[id]
	if i.State != store.ImportQueued {
		return store.BotImport{}, false, nil
	}
	i.State = store.ImportDownloading
	i.Attempts++
	return *i, true, nil
}
func (m *memoryImports) FinishImport(_ context.Context, id string, trackID, reason *string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	i := m.imports[id]
	i.State, i.TrackID, i.Error = store.ImportDone, trackID, reason
	if trackID == nil {
		i.State = store.ImportFailed
	}
	return nil
}
func (m *memoryImports) RequeueImport(_ context.Context, id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.imports[id].State = store.ImportQueued
	return nil
}
func (m *memoryImports) UnfinishedImports(context.Context, int) ([]store.BotImport, error) {
	return nil, nil
}

type memoryTracks struct{ ready, deleted []string }

func (m *memoryTracks) ReservePending(_ context.Context, ownerID string, t store.NewTrack, _ int64, _ int) (store.Track, error) {
	return store.Track{ID: "t1", OwnerID: ownerID, Title: t.Title, StorageKey: "users/" + ownerID + "/tracks/t1/" + t.FileName}, nil
}
func (m *memoryTracks) MarkReady(_ context.Context, ownerID, trackID string) (store.Track, error) {
	m.ready = append(m.ready, trackID)
	return store.Track{ID: trackID, OwnerID: ownerID}, nil
}
func (m *memoryTracks) Delete(_ context.Context, _, trackID string) error {
	m.deleted = append(m.deleted, trackID)
	return nil
}

type memoryObjects struct{ stored map[string][]byte }

func (m *memoryObjects) Put(_ context.Context, key string, r io.Reader, _ int64, _ string) error {
	data, err := io.ReadAll(r)
	m.stored[key] = data
	return err
}
func (m *memoryObjects) Remove(_ context.Context, key string) error {
	delete(m.stored, key)
	return nil
}

func TestServiceImportsTheBestLink(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/song":
			w.Header().Set("Content-Type", "text/html")
			fmt.Fprint(w, `<a href="/s-128.mp3">128</a><a href="/s-320.mp3">320</a>`)
		case "/s-320.mp3":
			w.Header().Set("Content-Length", strconv.Itoa(len(mp3)))
			w.Write(mp3)
		case "/fake.mp3":
			fmt.Fprint(w, "<html>not audio</html>")
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()
	fetcher := testFetcher(server)
	provider := NewProvider(fetcher, 1<<20)
	imports := &memoryImports{imports: map[string]*store.BotImport{}}
	tracks := &memoryTracks{}
	objects := &memoryObjects{stored: map[string][]byte{}}
	importer := bot.NewImporter(imports, tracks, objects, bot.UploadPolicy{Enabled: true, MaxFileBytes: 1 << 20, MaxOwnerBytes: 1 << 30, MaxPending: 3})
	service := NewService(fetcher, provider, importer, imports, 3)
	var queued []func()
	service.run = func(work func()) { queued = append(queued, work) }
	ctx := context.Background()

	job, err := service.Submit(ctx, "u1", server.URL+"/song")
	if err != nil || job.FileID != server.URL+"/s-320.mp3" || job.FileName != "s-320.mp3" || job.Provider != ProviderName {
		t.Fatalf("submit = %+v, %v", job, err)
	}
	// The same file can't be queued twice while it is in progress.
	if _, err := service.Submit(ctx, "u1", server.URL+"/s-320.mp3"); !errors.Is(err, ErrDuplicate) {
		t.Fatalf("duplicate: %v", err)
	}
	queued[0]()
	if got := imports.imports[job.ID]; got.State != store.ImportDone || len(tracks.ready) != 1 {
		t.Fatalf("after run = %+v, ready %v", got, tracks.ready)
	}
	if !bytes.Equal(objects.stored["users/u1/tracks/t1/s-320.mp3"], mp3) {
		t.Fatal("stored bytes differ from the download")
	}

	// A file that isn't really audio is refused and cleaned up.
	job, err = service.Submit(ctx, "u1", server.URL+"/fake.mp3")
	if err != nil {
		t.Fatal(err)
	}
	queued[1]()
	if got := imports.imports[job.ID]; got.State != store.ImportFailed || got.Error == nil || *got.Error != bot.ReasonInvalid {
		t.Fatalf("fake audio = %+v", got)
	}
	if len(tracks.deleted) != 1 || len(objects.stored) != 1 {
		t.Fatalf("not cleaned up: deleted %v, stored %d", tracks.deleted, len(objects.stored))
	}

	imports.active = 3
	if _, err := service.Submit(ctx, "u1", server.URL+"/song"); !errors.Is(err, ErrTooMany) {
		t.Fatalf("too many: %v", err)
	}
}
