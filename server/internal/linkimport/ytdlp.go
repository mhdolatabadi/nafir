package linkimport

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
	"unicode"

	"github.com/mhdolatabadi/nafir/server/internal/audio"
	"github.com/mhdolatabadi/nafir/server/internal/bot"
)

// YTDLPConfig sets up downloads from YouTube and Instagram.
type YTDLPConfig struct {
	// Path is the yt-dlp executable.
	Path string
	// Proxy, if set, is passed to yt-dlp for servers that can't reach the
	// sites directly.
	Proxy string
	// JSRuntimes is yt-dlp's --js-runtimes value, for example "node".
	JSRuntimes string
	// TempDir holds downloads while they are imported; empty is the
	// system's.
	TempDir string
	// MaxDuration is the longest video that may be imported.
	MaxDuration time.Duration
	// MaxConcurrent bounds yt-dlp processes running at once, server-wide.
	MaxConcurrent int
	// ProbeTimeout and DownloadTimeout bound one yt-dlp run.
	ProbeTimeout    time.Duration
	DownloadTimeout time.Duration
}

// YTDLP runs yt-dlp with fixed arguments and the canonical link only, never
// through a shell.
type YTDLP struct {
	config YTDLPConfig
	slots  chan struct{}
}

func NewYTDLP(config YTDLPConfig) *YTDLP {
	if config.MaxDuration <= 0 {
		config.MaxDuration = 30 * time.Minute
	}
	if config.MaxConcurrent <= 0 {
		config.MaxConcurrent = 2
	}
	if config.ProbeTimeout <= 0 {
		config.ProbeTimeout = 60 * time.Second
	}
	if config.DownloadTimeout <= 0 {
		config.DownloadTimeout = 10 * time.Minute
	}
	return &YTDLP{config: config, slots: make(chan struct{}, config.MaxConcurrent)}
}

// formatSelector prefers audio-only streams in a container rhythmo plays as
// is, then any audio-only stream, then a video whose audio is extracted.
const formatSelector = "bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio[ext=mp3]/bestaudio/best"

// MediaInfo is what a video's metadata says about the audio to import.
type MediaInfo struct {
	Title     string
	Artist    string
	Thumbnail string
	Duration  time.Duration
	// SizeBytes is the selected stream's size, if known.
	SizeBytes int64
	// Plan is how the audio is downloaded.
	Plan MediaPlan
}

// FileName names the imported track after its title.
func (m MediaInfo) FileName() string {
	return mediaFileName(m.Title) + "." + m.Plan.Ext
}

// MediaPlan is the stream to download and the file it becomes. It travels
// with the queued import, so the download keeps the format checked before.
type MediaPlan struct {
	FormatID string
	// Ext is the imported file's extension, without the dot.
	Ext string
	// Extract is set when the audio is copied out of a video, or out of a
	// container rhythmo doesn't play, without re-encoding it.
	Extract bool
}

// extractFormats maps an audio codec to yt-dlp's --audio-format that keeps
// it as is, and the extension that produces.
var extractFormats = []struct{ codec, format, ext string }{
	{"mp4a", "m4a", "m4a"}, {"aac", "m4a", "m4a"}, {"opus", "opus", "opus"},
	{"vorbis", "vorbis", "ogg"}, {"mp3", "mp3", "mp3"}, {"flac", "flac", "flac"},
}

func planFor(formatID, ext, acodec, vcodec string) (MediaPlan, bool) {
	if formatID == "" || strings.ContainsAny(formatID, "/,+[]") {
		return MediaPlan{}, false
	}
	ext, acodec = strings.ToLower(ext), strings.ToLower(acodec)
	audioOnly := vcodec == "none"
	if _, ok := audio.ContentType("a." + ext); ok && audioOnly {
		return MediaPlan{FormatID: formatID, Ext: ext}, true
	}
	if acodec == "" || acodec == "none" {
		return MediaPlan{}, false
	}
	for _, f := range extractFormats {
		if strings.HasPrefix(acodec, f.codec) {
			return MediaPlan{FormatID: formatID, Ext: f.ext, Extract: true}, true
		}
	}
	return MediaPlan{}, false
}

// fileID records the link and plan of a queued import.
func (p MediaPlan) fileID(link SocialLink) string {
	extract := "0"
	if p.Extract {
		extract = "1"
	}
	u := *link.URL
	u.Fragment = url.Values{"f": {p.FormatID}, "ext": {p.Ext}, "x": {extract}}.Encode()
	return u.String()
}

// parseMediaFileID reads back a queued social import's link and plan.
func parseMediaFileID(fileID string) (SocialLink, MediaPlan, bool) {
	u, err := ParseURL(fileID)
	if err != nil || u.Fragment == "" {
		return SocialLink{}, MediaPlan{}, false
	}
	values, err := url.ParseQuery(u.Fragment)
	if err != nil {
		return SocialLink{}, MediaPlan{}, false
	}
	u.Fragment = ""
	link, ok, err := DetectSocial(u)
	if !ok || err != nil || link.Site == SiteSpotify {
		return SocialLink{}, MediaPlan{}, false
	}
	plan, ok := planFor(values.Get("f"), values.Get("ext"), "", "none")
	if !ok || plan.Ext != values.Get("ext") {
		return SocialLink{}, MediaPlan{}, false
	}
	if values.Get("x") == "1" {
		plan.Extract = true
		valid := false
		for _, f := range extractFormats {
			valid = valid || f.ext == plan.Ext
		}
		if !valid {
			return SocialLink{}, MediaPlan{}, false
		}
	}
	return link, plan, true
}

func (y *YTDLP) baseArgs() []string {
	args := []string{
		"--ignore-config", "--no-playlist", "--no-cache-dir", "--no-mtime", "--no-progress",
		"--no-color", "--socket-timeout", "30", "--retries", "3", "--fragment-retries", "3",
	}
	if y.config.JSRuntimes != "" {
		args = append(args, "--js-runtimes", y.config.JSRuntimes)
	}
	if y.config.Proxy != "" {
		args = append(args, "--proxy", y.config.Proxy)
	}
	return args
}

// run starts yt-dlp in dir with a bare environment, so the server's own
// secrets and proxy settings never reach it.
func (y *YTDLP) run(ctx context.Context, dir string, timeout time.Duration, args []string) ([]byte, []byte, error) {
	select {
	case y.slots <- struct{}{}:
		defer func() { <-y.slots }()
	case <-ctx.Done():
		return nil, nil, ctx.Err()
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, y.config.Path, args...)
	cmd.Dir = dir
	cmd.Env = []string{"PATH=" + os.Getenv("PATH"), "HOME=" + dir, "XDG_CACHE_HOME=" + dir, "LANG=C.UTF-8"}
	stdout := &limitedBuffer{max: 8 << 20}
	stderr := &limitedBuffer{max: 64 << 10}
	cmd.Stdout, cmd.Stderr = stdout, stderr
	configureCommand(cmd)
	err := cmd.Run()
	if ctx.Err() != nil {
		err = fmt.Errorf("%w: yt-dlp timed out", ErrUnreachable)
	}
	return stdout.Bytes(), stderr.Bytes(), err
}

type ytdlpInfo struct {
	Title          string  `json:"title"`
	Track          string  `json:"track"`
	Artist         string  `json:"artist"`
	Creator        string  `json:"creator"`
	Uploader       string  `json:"uploader"`
	Channel        string  `json:"channel"`
	Thumbnail      string  `json:"thumbnail"`
	Duration       float64 `json:"duration"`
	IsLive         bool    `json:"is_live"`
	FormatID       string  `json:"format_id"`
	Ext            string  `json:"ext"`
	ACodec         string  `json:"acodec"`
	VCodec         string  `json:"vcodec"`
	FileSize       int64   `json:"filesize"`
	FileSizeApprox float64 `json:"filesize_approx"`
}

// Probe reads a video's metadata and picks the audio stream to import.
// Failures never carry yt-dlp's output, which names the link.
func (y *YTDLP) Probe(ctx context.Context, link SocialLink) (MediaInfo, error) {
	dir, err := os.MkdirTemp(y.config.TempDir, "rhythmo-probe-*")
	if err != nil {
		return MediaInfo{}, err
	}
	defer os.RemoveAll(dir)
	args := append(y.baseArgs(), "--dump-json", "--skip-download", "-f", formatSelector, "--", link.URL.String())
	stdout, stderr, err := y.run(ctx, dir, y.config.ProbeTimeout, args)
	if err != nil {
		return MediaInfo{}, probeError(stderr, err)
	}
	var info ytdlpInfo
	if err := json.Unmarshal(stdout, &info); err != nil {
		return MediaInfo{}, fmt.Errorf("%w: unreadable metadata", ErrUnreachable)
	}
	if info.IsLive {
		return MediaInfo{}, ErrUnsupported
	}
	plan, ok := planFor(info.FormatID, info.Ext, info.ACodec, info.VCodec)
	if !ok {
		return MediaInfo{}, ErrNoAudio
	}
	result := MediaInfo{
		Title: info.Title, Artist: info.Uploader, Thumbnail: thumbnailURL(info.Thumbnail),
		Duration: time.Duration(info.Duration * float64(time.Second)), Plan: plan,
		SizeBytes: info.FileSize,
	}
	if result.SizeBytes <= 0 {
		result.SizeBytes = int64(info.FileSizeApprox)
	}
	if info.Channel != "" {
		result.Artist = info.Channel
	}
	// YouTube Music names the song and its artists itself.
	if info.Track != "" {
		result.Title = info.Track
	}
	if a := firstNonEmpty(info.Artist, info.Creator); a != "" {
		result.Artist = a
	}
	result.Artist = strings.TrimSuffix(strings.TrimSpace(result.Artist), " - Topic")
	result.Title = strings.TrimSpace(result.Title)
	if result.Duration <= 0 {
		return MediaInfo{}, ErrUnsupported
	}
	if result.Duration > y.config.MaxDuration {
		return MediaInfo{}, ErrTooLong
	}
	return result, nil
}

// probeError keeps only why yt-dlp refused, not what it printed.
func probeError(stderr []byte, err error) error {
	if errors.Is(err, ErrUnreachable) || errors.Is(err, context.Canceled) {
		return err
	}
	text := strings.ToLower(string(stderr))
	switch {
	case strings.Contains(text, "unsupported url"):
		return ErrUnsupported
	case strings.Contains(text, "requested format is not available"), strings.Contains(text, "no video formats"):
		return ErrNoAudio
	}
	return fmt.Errorf("%w: yt-dlp failed", ErrUnreachable)
}

// Open downloads the planned stream into a temporary directory and opens
// the result. Closing the file removes the directory.
func (y *YTDLP) Open(ctx context.Context, link SocialLink, plan MediaPlan, maxBytes int64) (io.ReadCloser, int64, error) {
	dir, err := os.MkdirTemp(y.config.TempDir, "rhythmo-ytdlp-*")
	if err != nil {
		return nil, 0, err
	}
	keep := false
	defer func() {
		if !keep {
			os.RemoveAll(dir)
		}
	}()
	args := append(y.baseArgs(),
		"-f", plan.FormatID,
		"-o", filepath.Join(dir, "audio.%(ext)s"),
		"--max-filesize", strconv.FormatInt(maxBytes, 10),
		"--match-filter", fmt.Sprintf("!is_live & duration <= %d", int64(y.config.MaxDuration/time.Second)),
		"--no-write-thumbnail", "--no-embed-metadata", "--no-embed-thumbnail",
	)
	if plan.Extract {
		format := ""
		for _, f := range extractFormats {
			if f.ext == plan.Ext {
				format = f.format
				break
			}
		}
		args = append(args, "--extract-audio", "--audio-format", format)
	}
	args = append(args, "--", link.URL.String())
	stdout, stderr, err := y.run(ctx, dir, y.config.DownloadTimeout, args)
	// yt-dlp reports a refused size on stdout and still exits cleanly.
	if strings.Contains(string(stdout), "larger than max-filesize") || strings.Contains(string(stderr), "larger than max-filesize") {
		return nil, 0, bot.ErrFileTooLarge
	}
	if err != nil {
		return nil, 0, probeError(stderr, err)
	}
	file, err := os.Open(filepath.Join(dir, "audio."+plan.Ext))
	if err != nil {
		// Skipped by the duration filter, or produced something else.
		return nil, 0, fmt.Errorf("%w: no %s output", ErrNoAudio, plan.Ext)
	}
	stat, err := file.Stat()
	if err != nil {
		file.Close()
		return nil, 0, err
	}
	if stat.Size() > maxBytes {
		file.Close()
		return nil, 0, bot.ErrFileTooLarge
	}
	keep = true
	return &tempDirFile{File: file, dir: dir}, stat.Size(), nil
}

// tempDirFile removes its directory when closed.
type tempDirFile struct {
	*os.File
	dir string
}

func (t *tempDirFile) Close() error {
	err := t.File.Close()
	os.RemoveAll(t.dir)
	return err
}

// thumbnailHosts serve the sites' preview images.
var thumbnailHosts = []string{"ytimg.com", "ggpht.com", "googleusercontent.com", "cdninstagram.com", "fbcdn.net"}

// thumbnailURL keeps a preview image only if it is served over https by one
// of the sites' image hosts.
func thumbnailURL(raw string) string {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.User != nil || u.Port() != "" || len(raw) > maxURLLength {
		return ""
	}
	host := strings.ToLower(u.Hostname())
	for _, allowed := range thumbnailHosts {
		if host == allowed || strings.HasSuffix(host, "."+allowed) {
			return u.String()
		}
	}
	return ""
}

// mediaFileName makes a title safe to use as a file name on Web and Android.
func mediaFileName(title string) string {
	name := strings.Map(func(r rune) rune {
		if strings.ContainsRune(`/\<>:"|?*`, r) || unicode.IsControl(r) || unicode.Is(unicode.Bidi_Control, r) {
			return ' '
		}
		return r
	}, title)
	name = strings.Join(strings.Fields(name), " ")
	name = strings.Trim(name, ". ")
	if r := []rune(name); len(r) > 120 {
		name = strings.TrimSpace(string(r[:120]))
	}
	if name == "" {
		return "track"
	}
	return name
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v = strings.TrimSpace(v); v != "" {
			return v
		}
	}
	return ""
}

// limitedBuffer keeps at most max bytes and drops the rest.
type limitedBuffer struct {
	bytes.Buffer
	max int
}

func (b *limitedBuffer) Write(p []byte) (int, error) {
	if room := b.max - b.Len(); room > 0 {
		if len(p) > room {
			b.Buffer.Write(p[:room])
		} else {
			b.Buffer.Write(p)
		}
	}
	return len(p), nil
}
