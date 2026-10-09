package linkimport

import (
	"context"
	"io"
	"mime"
	"net/url"
	"path"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/audio"
	"golang.org/x/net/html"
)

// Candidate is the audio file a link leads to.
type Candidate struct {
	URL *url.URL
	// FileName has a supported audio extension; it names the track.
	FileName string
	// SizeBytes is the file's size when it is already known, else 0.
	SizeBytes int64
	// Title, Artist, Thumbnail and Duration come from a video's metadata.
	Title     string
	Artist    string
	Thumbnail string
	Duration  time.Duration
}

var extensionsByType = map[string]string{
	"audio/mpeg": ".mp3", "audio/mp3": ".mp3", "audio/mp4": ".m4a", "audio/x-m4a": ".m4a",
	"audio/m4a": ".m4a", "audio/aac": ".aac", "audio/flac": ".flac", "audio/x-flac": ".flac",
	"audio/ogg": ".ogg", "audio/opus": ".opus", "audio/wav": ".wav", "audio/x-wav": ".wav",
	"audio/wave": ".wav", "audio/webm": ".webm",
}

// Resolve finds the audio file a link leads to. A link to an audio file is
// that file; a web page is searched for links to audio files, and the best
// quality one is picked.
func (f *Fetcher) Resolve(ctx context.Context, u *url.URL) (Candidate, error) {
	ctx, cancel := context.WithTimeout(ctx, pageTimeout)
	defer cancel()
	resp, err := f.get(ctx, u)
	if err != nil {
		return Candidate{}, err
	}
	defer resp.Body.Close()
	final := resp.Request.URL
	mediaType, _, _ := mime.ParseMediaType(resp.Header.Get("Content-Type"))

	if name, ok := audioFileName(final, mediaType); ok {
		size := resp.ContentLength
		if size < 0 {
			size = 0
		}
		return Candidate{URL: final, FileName: name, SizeBytes: size}, nil
	}
	if mediaType != "text/html" && mediaType != "application/xhtml+xml" {
		return Candidate{}, ErrUnsupported
	}
	page, err := io.ReadAll(io.LimitReader(resp.Body, maxPageBytes))
	if err != nil {
		return Candidate{}, ErrUnreachable
	}
	best, ok := bestLink(final, string(page))
	if !ok {
		return Candidate{}, ErrNoAudio
	}
	name, _ := audioFileName(best, "")
	return Candidate{URL: best, FileName: name}, nil
}

// ResolveAll finds every supported audio file a link leads to. A link to an
// audio file is that file; a web page is searched for all audio links it names.
func (f *Fetcher) ResolveAll(ctx context.Context, u *url.URL) ([]Candidate, error) {
	ctx, cancel := context.WithTimeout(ctx, pageTimeout)
	defer cancel()
	resp, err := f.get(ctx, u)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	final := resp.Request.URL
	mediaType, _, _ := mime.ParseMediaType(resp.Header.Get("Content-Type"))

	if name, ok := audioFileName(final, mediaType); ok {
		size := resp.ContentLength
		if size < 0 {
			size = 0
		}
		return []Candidate{{URL: final, FileName: name, SizeBytes: size}}, nil
	}
	if mediaType != "text/html" && mediaType != "application/xhtml+xml" {
		return nil, ErrUnsupported
	}
	page, err := io.ReadAll(io.LimitReader(resp.Body, maxPageBytes))
	if err != nil {
		return nil, ErrUnreachable
	}
	links := findLinks(final, string(page))
	if len(links) == 0 {
		return nil, ErrNoAudio
	}
	candidates := make([]Candidate, 0, len(links))
	for _, l := range links {
		name, _ := audioFileName(l.url, "")
		candidates = append(candidates, Candidate{URL: l.url, FileName: name})
	}
	return candidates, nil
}

// audioFileName names the file at u, if it is supported audio: by the
// extension in its path, or else by its content type.
func audioFileName(u *url.URL, mediaType string) (string, bool) {
	base, err := url.PathUnescape(path.Base(u.Path))
	if err != nil || base == "." || base == "/" {
		base = ""
	}
	if _, ok := audio.ContentType(base); ok {
		return base, true
	}
	ext, ok := extensionsByType[strings.ToLower(mediaType)]
	if !ok {
		return "", false
	}
	stem := strings.TrimSuffix(base, path.Ext(base))
	if stem == "" {
		stem = "track"
	}
	return stem + ext, true
}

type link struct {
	url   *url.URL
	label string
	order int
}

// bestLink returns the highest quality audio file the page links to:
// lossless first, then the highest bitrate named in the link or its text,
// then the first on the page.
func bestLink(base *url.URL, page string) (*url.URL, bool) {
	links := findLinks(base, page)
	var best *link
	bestScore := -1
	for i := range links {
		if score := quality(links[i]); score > bestScore {
			best, bestScore = &links[i], score
		}
	}
	if best == nil {
		return nil, false
	}
	return best.url, true
}

// findLinks lists links to supported audio files: <a href>, <audio src>,
// <source src> and og:audio meta tags, resolved against the page.
func findLinks(base *url.URL, page string) []link {
	var links []link
	seen := map[string]bool{}
	add := func(raw, label string) {
		raw = strings.TrimSpace(raw)
		if raw == "" {
			return
		}
		ref, err := url.Parse(raw)
		if err != nil {
			return
		}
		u := base.ResolveReference(ref)
		if u.Scheme != "http" && u.Scheme != "https" {
			return
		}
		if _, ok := audioFileName(u, ""); !ok || seen[u.String()] {
			return
		}
		seen[u.String()] = true
		links = append(links, link{url: u, label: label, order: len(links)})
	}

	tokens := html.NewTokenizer(strings.NewReader(page))
	var open *link // the <a> whose text is being read
	var text strings.Builder
	for {
		switch tokens.Next() {
		case html.ErrorToken:
			return links
		case html.StartTagToken, html.SelfClosingTagToken:
			token := tokens.Token()
			attrs := map[string]string{}
			for _, a := range token.Attr {
				attrs[strings.ToLower(a.Key)] = a.Val
			}
			switch token.Data {
			case "a":
				open = &link{label: attrs["href"]}
				text.Reset()
			case "audio", "source":
				add(attrs["src"], attrs["title"])
			case "meta":
				property := strings.ToLower(attrs["property"])
				if property == "og:audio" || property == "og:audio:url" || property == "og:audio:secure_url" {
					add(attrs["content"], "")
				}
			}
		case html.TextToken:
			if open != nil && text.Len() < 500 {
				text.Write(tokens.Text())
			}
		case html.EndTagToken:
			if name, _ := tokens.TagName(); string(name) == "a" && open != nil {
				add(open.label, text.String())
				open = nil
			}
		}
	}
}

var bitrates = regexp.MustCompile(`(?i)(?:^|[^0-9])(64|96|128|160|192|256|320)(?:[^0-9]|$)`)

// quality scores a link: lossless highest, then the bitrate it names.
func quality(l link) int {
	text := strings.ToLower(l.url.Path + " " + l.label)
	ext := strings.ToLower(path.Ext(l.url.Path))
	if ext == ".flac" || ext == ".wav" || strings.Contains(text, "lossless") {
		return 1000
	}
	best := 0
	for _, m := range bitrates.FindAllStringSubmatch(text, -1) {
		if n, _ := strconv.Atoi(m[1]); n > best {
			best = n
		}
	}
	return best
}
