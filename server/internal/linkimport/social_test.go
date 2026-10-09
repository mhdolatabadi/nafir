package linkimport

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/bot"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

func TestDetectSocial(t *testing.T) {
	for _, tc := range []struct {
		raw, site, canonical string
	}{
		{"https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42&list=PL1", SiteYouTube, "https://www.youtube.com/watch?v=dQw4w9WgXcQ"},
		{"https://youtu.be/dQw4w9WgXcQ?si=abc", SiteYouTube, "https://www.youtube.com/watch?v=dQw4w9WgXcQ"},
		{"https://m.youtube.com/shorts/dQw4w9WgXcQ", SiteYouTube, "https://www.youtube.com/watch?v=dQw4w9WgXcQ"},
		{"https://music.youtube.com/watch?v=dQw4w9WgXcQ", SiteYouTube, "https://www.youtube.com/watch?v=dQw4w9WgXcQ"},
		{"https://www.instagram.com/reel/C1a2B3c4D5e/?igsh=x", SiteInstagram, "https://www.instagram.com/reel/C1a2B3c4D5e/"},
		{"https://instagram.com/someone/p/C1a2B3c4D5e", SiteInstagram, "https://www.instagram.com/p/C1a2B3c4D5e/"},
		{"https://open.spotify.com/intl-de/track/4uLU6hMCjMI75M1A2tKUQC?si=1", SiteSpotify, "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"},
		{"https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M", SiteSpotify, "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"},
	} {
		link, ok, err := DetectSocial(mustParse(t, tc.raw))
		if !ok || err != nil || link.Site != tc.site || link.URL.String() != tc.canonical {
			t.Errorf("DetectSocial(%s) = %+v %v %v", tc.raw, link, ok, err)
		}
	}
	// Recognised sites, but not one video, post or Spotify item.
	for _, raw := range []string{
		"https://www.youtube.com/playlist?list=PL1", "https://www.youtube.com/watch?v=short",
		"https://www.youtube.com/watch?v=dQw4w9WgXcQ;rm", "https://www.youtube.com/@channel",
		"https://www.instagram.com/someone/", "https://www.instagram.com/stories/a/1",
		"https://open.spotify.com/artist/4uLU6hMCjMI75M1A2tKUQC", "https://open.spotify.com/track/short",
		"https://www.youtube.com:8080/watch?v=dQw4w9WgXcQ",
	} {
		if _, ok, err := DetectSocial(mustParse(t, raw)); !ok || !errors.Is(err, ErrUnsupported) {
			t.Errorf("DetectSocial(%s) = %v, %v", raw, ok, err)
		}
	}
	// Look-alike hosts are other sites.
	for _, raw := range []string{"https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ", "https://notyoutube.com/watch?v=dQw4w9WgXcQ"} {
		if _, ok, _ := DetectSocial(mustParse(t, raw)); ok {
			t.Errorf("DetectSocial(%s) recognised a look-alike", raw)
		}
	}
}

var m4a = append([]byte("\x00\x00\x00\x18ftypM4A \x00\x00\x00\x00"), bytes.Repeat([]byte{1}, 300)...)

// fakeYTDLP writes a yt-dlp stand-in: it records its arguments, prints info
// for --dump-json, and otherwise writes out to the -o template with ext.
type fakeYTDLP struct {
	dir      string
	path     string
	argsFile string
}

func newFakeYTDLP(t *testing.T, info string, ext string, out []byte, extra string) *fakeYTDLP {
	t.Helper()
	dir := t.TempDir()
	f := &fakeYTDLP{dir: dir, path: filepath.Join(dir, "yt-dlp"), argsFile: filepath.Join(dir, "args")}
	if err := os.WriteFile(filepath.Join(dir, "info.json"), []byte(info), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "audio.bin"), out, 0o600); err != nil {
		t.Fatal(err)
	}
	script := fmt.Sprintf(`#!/bin/sh
printf '%%s\n' "$@" > %[1]q
env > %[1]q.env
%[4]s
case " $* " in *" --dump-json "*) cat %[2]q; exit 0;; esac
out=""; prev=""
for a in "$@"; do if [ "$prev" = "-o" ]; then out="$a"; fi; prev="$a"; done
cp %[3]q "${out%%.%%(ext)s}.%[5]s"
`, f.argsFile, filepath.Join(dir, "info.json"), filepath.Join(dir, "audio.bin"), extra, ext)
	if err := os.WriteFile(f.path, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	return f
}

func (f *fakeYTDLP) args(t *testing.T) []string {
	t.Helper()
	data, err := os.ReadFile(f.argsFile)
	if err != nil {
		t.Fatal(err)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}

const youTubeInfo = `{"title":"Official Video","track":"Song","artist":"Singer","channel":"Singer - Topic",
"thumbnail":"https://i.ytimg.com/vi/dQw4w9WgXcQ/hq.jpg","duration":215.4,"format_id":"140","ext":"m4a",
"acodec":"mp4a.40.2","vcodec":"none","filesize":3400000}`

func youTubeLink(t *testing.T) SocialLink {
	link, _, err := DetectSocial(mustParse(t, "https://youtu.be/dQw4w9WgXcQ"))
	if err != nil {
		t.Fatal(err)
	}
	return link
}

func TestYTDLPProbe(t *testing.T) {
	fake := newFakeYTDLP(t, youTubeInfo, "m4a", m4a, "")
	y := NewYTDLP(YTDLPConfig{Path: fake.path, Proxy: "socks5://proxy.example:1080", JSRuntimes: "node", TempDir: t.TempDir()})
	t.Setenv("AUTH_TOKEN_SECRET", "not-for-yt-dlp")
	info, err := y.Probe(context.Background(), youTubeLink(t))
	if err != nil {
		t.Fatal(err)
	}
	if info.Title != "Song" || info.Artist != "Singer" || info.Duration != 215400*time.Millisecond ||
		info.Thumbnail == "" || info.SizeBytes != 3400000 || info.Plan != (MediaPlan{FormatID: "140", Ext: "m4a"}) {
		t.Fatalf("info = %+v", info)
	}
	if info.FileName() != "Song.m4a" {
		t.Fatalf("file name = %q", info.FileName())
	}
	args := fake.args(t)
	joined := strings.Join(args, " ")
	for _, want := range []string{"--ignore-config", "--no-playlist", "--proxy socks5://proxy.example:1080", "--js-runtimes node", "--dump-json"} {
		if !strings.Contains(joined, want) {
			t.Errorf("args %q lack %q", joined, want)
		}
	}
	// The link is the canonical one, last, after "--".
	if args[len(args)-2] != "--" || args[len(args)-1] != "https://www.youtube.com/watch?v=dQw4w9WgXcQ" {
		t.Fatalf("args end with %q", args[len(args)-2:])
	}
	env, _ := os.ReadFile(fake.argsFile + ".env")
	if strings.Contains(string(env), "AUTH_TOKEN_SECRET") {
		t.Fatal("yt-dlp inherited the server's environment")
	}
}

func TestYTDLPProbeRefusals(t *testing.T) {
	ctx := context.Background()
	for name, tc := range map[string]struct {
		info  string
		extra string
		want  error
	}{
		"too long":    {`{"title":"x","duration":7200,"format_id":"140","ext":"m4a","acodec":"mp4a","vcodec":"none"}`, "", ErrTooLong},
		"live":        {`{"title":"x","is_live":true,"format_id":"140","ext":"m4a","acodec":"mp4a","vcodec":"none"}`, "", ErrUnsupported},
		"no audio":    {`{"title":"x","duration":10,"format_id":"1","ext":"mp4","acodec":"none","vcodec":"avc1"}`, "", ErrNoAudio},
		"odd codec":   {`{"title":"x","duration":10,"format_id":"1","ext":"mp4","acodec":"ac-3","vcodec":"avc1"}`, "", ErrNoAudio},
		"unsupported": {"", `echo "ERROR: Unsupported URL: https://x" >&2; exit 1`, ErrUnsupported},
		"failure":     {"", `echo "ERROR: Private video" >&2; exit 1`, ErrUnreachable},
		"garbage":     {"not json", "", ErrUnreachable},
	} {
		fake := newFakeYTDLP(t, tc.info, "m4a", m4a, tc.extra)
		y := NewYTDLP(YTDLPConfig{Path: fake.path, MaxDuration: time.Hour / 2})
		_, err := y.Probe(ctx, youTubeLink(t))
		if !errors.Is(err, tc.want) {
			t.Errorf("%s: %v", name, err)
		}
		if err != nil && strings.Contains(err.Error(), "youtube") {
			t.Errorf("%s: error names the link: %v", name, err)
		}
	}
}

func TestPlanFor(t *testing.T) {
	for _, tc := range []struct {
		formatID, ext, acodec, vcodec string
		want                          MediaPlan
		ok                            bool
	}{
		{"140", "m4a", "mp4a.40.2", "none", MediaPlan{FormatID: "140", Ext: "m4a"}, true},
		{"251", "webm", "opus", "none", MediaPlan{FormatID: "251", Ext: "webm"}, true},
		// An Instagram reel with audio only inside the video: copied out.
		{"8", "mp4", "mp4a.40.5", "avc1", MediaPlan{FormatID: "8", Ext: "m4a", Extract: true}, true},
		{"x", "mka", "opus", "none", MediaPlan{FormatID: "x", Ext: "opus", Extract: true}, true},
		{"140+251", "m4a", "mp4a", "none", MediaPlan{}, false},
		{"", "m4a", "mp4a", "none", MediaPlan{}, false},
	} {
		got, ok := planFor(tc.formatID, tc.ext, tc.acodec, tc.vcodec)
		if got != tc.want || ok != tc.ok {
			t.Errorf("planFor(%s, %s, %s, %s) = %+v, %v", tc.formatID, tc.ext, tc.acodec, tc.vcodec, got, ok)
		}
	}
	link := youTubeLink(t)
	plan := MediaPlan{FormatID: "8", Ext: "m4a", Extract: true}
	gotLink, gotPlan, ok := parseMediaFileID(plan.fileID(link))
	if !ok || gotPlan != plan || gotLink.URL.String() != link.URL.String() {
		t.Fatalf("round trip = %+v %+v %v", gotLink, gotPlan, ok)
	}
	for _, id := range []string{
		"https://www.youtube.com/watch?v=dQw4w9WgXcQ", "https://example.com/a.mp3#f=1&ext=m4a&x=0",
		"https://www.youtube.com/watch?v=dQw4w9WgXcQ#f=1&ext=exe&x=0", "https://www.youtube.com/watch?v=dQw4w9WgXcQ#f=1/best&ext=m4a&x=0",
		"https://www.youtube.com/watch?v=dQw4w9WgXcQ#f=1&ext=webm&x=1",
	} {
		if _, _, ok := parseMediaFileID(id); ok {
			t.Errorf("parseMediaFileID(%s) accepted", id)
		}
	}
}

func emptyDir(t *testing.T, dir string) {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		t.Fatalf("temporary files left behind: %v", entries)
	}
}

func TestYTDLPOpen(t *testing.T) {
	ctx := context.Background()
	link := youTubeLink(t)

	fake := newFakeYTDLP(t, "", "m4a", m4a, "")
	temp := t.TempDir()
	y := NewYTDLP(YTDLPConfig{Path: fake.path, TempDir: temp})
	body, size, err := y.Open(ctx, link, MediaPlan{FormatID: "18", Ext: "m4a", Extract: true}, 1<<20)
	if err != nil || size != int64(len(m4a)) {
		t.Fatalf("open = %d, %v", size, err)
	}
	if data, _ := io.ReadAll(body); !bytes.Equal(data, m4a) {
		t.Fatal("downloaded bytes differ")
	}
	body.Close()
	emptyDir(t, temp)
	joined := strings.Join(fake.args(t), " ")
	for _, want := range []string{"-f 18", "--max-filesize 1048576", "--extract-audio --audio-format m4a", "--match-filter !is_live & duration <= 1800"} {
		if !strings.Contains(joined, want) {
			t.Errorf("args %q lack %q", joined, want)
		}
	}

	// Larger than allowed, failing, wrong output and timing out all leave
	// nothing behind.
	small := NewYTDLP(YTDLPConfig{Path: fake.path, TempDir: temp})
	if _, _, err := small.Open(ctx, link, MediaPlan{FormatID: "140", Ext: "m4a"}, 100); !errors.Is(err, bot.ErrFileTooLarge) {
		t.Fatalf("too large: %v", err)
	}
	emptyDir(t, temp)

	refused := newFakeYTDLP(t, "", "m4a", m4a, `echo "[download] File is larger than max-filesize (3449447 bytes > 1000 bytes). Aborting."; exit 0`)
	if _, _, err := NewYTDLP(YTDLPConfig{Path: refused.path, TempDir: temp}).Open(ctx, link, MediaPlan{FormatID: "140", Ext: "m4a"}, 1<<20); !errors.Is(err, bot.ErrFileTooLarge) {
		t.Fatalf("refused by yt-dlp: %v", err)
	}
	emptyDir(t, temp)

	failing := newFakeYTDLP(t, "", "m4a", m4a, `touch "$PWD/partial.part"; exit 1`)
	if _, _, err := NewYTDLP(YTDLPConfig{Path: failing.path, TempDir: temp}).Open(ctx, link, MediaPlan{FormatID: "140", Ext: "m4a"}, 1<<20); !errors.Is(err, ErrUnreachable) {
		t.Fatalf("failing: %v", err)
	}
	emptyDir(t, temp)

	wrong := newFakeYTDLP(t, "", "webm", m4a, "")
	if _, _, err := NewYTDLP(YTDLPConfig{Path: wrong.path, TempDir: temp}).Open(ctx, link, MediaPlan{FormatID: "140", Ext: "m4a"}, 1<<20); !errors.Is(err, ErrNoAudio) {
		t.Fatalf("wrong output: %v", err)
	}
	emptyDir(t, temp)

	slow := newFakeYTDLP(t, "", "m4a", m4a, `sleep 30`)
	start := time.Now()
	_, _, err = NewYTDLP(YTDLPConfig{Path: slow.path, TempDir: temp, DownloadTimeout: 200 * time.Millisecond}).
		Open(ctx, link, MediaPlan{FormatID: "140", Ext: "m4a"}, 1<<20)
	if !errors.Is(err, ErrUnreachable) || time.Since(start) > 10*time.Second {
		t.Fatalf("timeout: %v after %v", err, time.Since(start))
	}
	emptyDir(t, temp)
}

func TestServiceImportsFromYouTube(t *testing.T) {
	fake := newFakeYTDLP(t, youTubeInfo, "m4a", m4a, "")
	fetcher := testFetcher()
	provider := NewProvider(fetcher, 1<<30)
	imports := &memoryImports{imports: map[string]*store.BotImport{}}
	tracks := &memoryTracks{}
	objects := &memoryObjects{stored: map[string][]byte{}}
	importer := bot.NewImporter(imports, tracks, objects, bot.UploadPolicy{Enabled: true, MaxFileBytes: 1 << 30, MaxOwnerBytes: 1 << 30, MaxPending: 3})
	service := NewService(fetcher, provider, importer, imports, 3)
	var queued []func()
	service.run = func(work func()) { queued = append(queued, work) }
	ctx := context.Background()

	// Without yt-dlp, these links are refused rather than scraped.
	if _, err := service.Preview(ctx, "u1", "https://youtu.be/dQw4w9WgXcQ"); !errors.Is(err, ErrUnsupported) {
		t.Fatalf("without yt-dlp: %v", err)
	}
	service.WithMedia(NewYTDLP(YTDLPConfig{Path: fake.path, TempDir: t.TempDir()}))

	candidates, err := service.Preview(ctx, "u1", "https://youtu.be/dQw4w9WgXcQ")
	if err != nil || len(candidates) != 1 || candidates[0].Title != "Song" || candidates[0].Artist != "Singer" ||
		candidates[0].URL.String() != "https://www.youtube.com/watch?v=dQw4w9WgXcQ" {
		t.Fatalf("preview = %+v, %v", candidates, err)
	}
	job, err := service.Submit(ctx, "u1", candidates[0].URL.String())
	if err != nil || job.FileName != "Song.m4a" || job.Title == nil || *job.Title != "Song" || job.Artist == nil || *job.Artist != "Singer" {
		t.Fatalf("submit = %+v, %v", job, err)
	}
	if u, _ := url.Parse(job.FileID); u.Hostname() != "www.youtube.com" {
		t.Fatalf("file ID = %s", job.FileID)
	}
	if _, err := service.Submit(ctx, "u1", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"); !errors.Is(err, ErrDuplicate) {
		t.Fatalf("duplicate: %v", err)
	}
	queued[0]()
	if got := imports.imports[job.ID]; got.State != store.ImportDone {
		t.Fatalf("after run = %+v", got)
	}
	if !bytes.Equal(objects.stored["users/u1/tracks/t1/Song.m4a"], m4a) {
		t.Fatalf("stored = %v", objects.stored)
	}

	// The estimated size already counts against the upload limit.
	limited := bot.NewImporter(imports, tracks, objects, bot.UploadPolicy{Enabled: true, MaxFileBytes: 1000, MaxOwnerBytes: 1 << 30, MaxPending: 3})
	tight := NewService(fetcher, NewProvider(fetcher, 1000), limited, imports, 3).WithMedia(NewYTDLP(YTDLPConfig{Path: fake.path}))
	if _, err := tight.Submit(ctx, "u1", "https://youtu.be/dQw4w9WgXcQ"); !errors.Is(err, ErrTooLarge) {
		t.Fatalf("too large: %v", err)
	}

	// Spotify links have no audio to download.
	if _, err := service.Submit(ctx, "u1", "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"); !errors.Is(err, ErrMetadataOnly) {
		t.Fatalf("spotify: %v", err)
	}
}
