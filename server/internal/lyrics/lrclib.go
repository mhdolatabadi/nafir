// Package lyrics looks song lyrics up in LRCLIB (https://lrclib.net), a free
// and open lyrics database with synced (timed) lyrics, and caches the answer
// per track. Only the server talks to LRCLIB: the app never does, so the
// listener's address is not exposed and lyrics work wherever the API does.
package lyrics

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

var (
	// ErrNotFound means LRCLIB has no lyrics for the song.
	ErrNotFound = errors.New("lyrics not found")
	// ErrUnavailable means LRCLIB could not be asked right now: it timed
	// out, failed, or our own request budget is spent.
	ErrUnavailable = errors.New("lyrics service unavailable")
)

const (
	// DefaultBaseURL is LRCLIB's public API.
	DefaultBaseURL = "https://lrclib.net"
	// UserAgent names the app, as LRCLIB asks every client to.
	UserAgent = "rhythmo (https://github.com/mhdolatabadi/nafir)"

	defaultTimeout = 8 * time.Second
	// maxResponseBytes bounds one LRCLIB answer; a search returns at most
	// 20 records, each with two copies of the lyrics.
	maxResponseBytes = 2 << 20
	// MaxLyricsBytes is the longest lyrics text kept; anything longer is not
	// a song.
	MaxLyricsBytes = 64 << 10
	maxFieldLength = 300
)

// Record is one LRCLIB entry.
type Record struct {
	ID           int64   `json:"id"`
	TrackName    string  `json:"trackName"`
	ArtistName   string  `json:"artistName"`
	AlbumName    string  `json:"albumName"`
	Duration     float64 `json:"duration"`
	Instrumental bool    `json:"instrumental"`
	PlainLyrics  *string `json:"plainLyrics"`
	SyncedLyrics *string `json:"syncedLyrics"`
}

// HasLyrics reports whether the record carries any text to show, or is a
// known instrumental.
func (r Record) HasLyrics() bool {
	return r.Instrumental || nonEmpty(r.PlainLyrics) || nonEmpty(r.SyncedLyrics)
}

func nonEmpty(s *string) bool {
	return s != nil && strings.TrimSpace(*s) != ""
}

// Query describes the song to look up. Duration is zero when unknown.
type Query struct {
	Title    string
	Artist   string
	Album    string
	Duration time.Duration
	// Text, when set, is free text searched in every field instead.
	Text string
}

// Source is what the service needs from LRCLIB; *Client implements it.
type Source interface {
	// Get is LRCLIB's exact lookup by title, artist, album and duration.
	Get(ctx context.Context, q Query) (Record, error)
	// ByID fetches one record.
	ByID(ctx context.Context, id int64) (Record, error)
	// Search lists records that loosely match.
	Search(ctx context.Context, q Query) ([]Record, error)
}

// Client calls LRCLIB's HTTP API, at most one request per interval across
// the whole process.
type Client struct {
	base    *url.URL
	http    *http.Client
	limiter *intervalLimiter
}

// ClientConfig configures a Client; zero values pick defaults.
type ClientConfig struct {
	BaseURL string
	Timeout time.Duration
	// Interval is the least time between two requests to LRCLIB.
	Interval time.Duration
	// MaxWait is the longest a lookup queues for its turn before it gives
	// up with ErrUnavailable instead of piling up.
	MaxWait time.Duration
}

// NewClient builds a client for LRCLIB, or for a fake one in tests.
func NewClient(config ClientConfig) (*Client, error) {
	raw := config.BaseURL
	if raw == "" {
		raw = DefaultBaseURL
	}
	base, err := url.Parse(raw)
	if err != nil || (base.Scheme != "http" && base.Scheme != "https") || base.Host == "" {
		return nil, fmt.Errorf("invalid LRCLIB base URL %q", raw)
	}
	timeout := config.Timeout
	if timeout <= 0 {
		timeout = defaultTimeout
	}
	interval := config.Interval
	if interval <= 0 {
		interval = 200 * time.Millisecond
	}
	maxWait := config.MaxWait
	if maxWait <= 0 {
		maxWait = 3 * time.Second
	}
	return &Client{
		base:    base,
		http:    &http.Client{Timeout: timeout},
		limiter: &intervalLimiter{interval: interval, maxWait: maxWait, now: time.Now},
	}, nil
}

func (c *Client) Get(ctx context.Context, q Query) (Record, error) {
	params := url.Values{}
	params.Set("track_name", q.Title)
	params.Set("artist_name", q.Artist)
	if q.Album != "" {
		params.Set("album_name", q.Album)
	}
	if q.Duration > 0 {
		params.Set("duration", strconv.Itoa(int((q.Duration+time.Second/2)/time.Second)))
	}
	var record Record
	err := c.call(ctx, "/api/get", params, &record)
	return record, err
}

func (c *Client) ByID(ctx context.Context, id int64) (Record, error) {
	var record Record
	err := c.call(ctx, "/api/get/"+strconv.FormatInt(id, 10), nil, &record)
	return record, err
}

func (c *Client) Search(ctx context.Context, q Query) ([]Record, error) {
	params := url.Values{}
	if q.Text != "" {
		params.Set("q", q.Text)
	} else {
		params.Set("track_name", q.Title)
		if q.Artist != "" {
			params.Set("artist_name", q.Artist)
		}
	}
	var records []Record
	if err := c.call(ctx, "/api/search", params, &records); err != nil {
		return nil, err
	}
	return records, nil
}

// call GETs path and decodes the JSON answer into out. LRCLIB's 404 is
// ErrNotFound; anything else that goes wrong is ErrUnavailable.
func (c *Client) call(ctx context.Context, path string, params url.Values, out any) error {
	if err := c.limiter.wait(ctx); err != nil {
		return err
	}
	endpoint := c.base.JoinPath(path)
	endpoint.RawQuery = params.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint.String(), nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", UserAgent)
	req.Header.Set("Accept", "application/json")
	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrUnavailable, err)
	}
	defer resp.Body.Close()
	switch {
	case resp.StatusCode == http.StatusNotFound:
		return ErrNotFound
	case resp.StatusCode != http.StatusOK:
		return fmt.Errorf("%w: LRCLIB answered HTTP %d", ErrUnavailable, resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes+1))
	if err != nil {
		return fmt.Errorf("%w: %v", ErrUnavailable, err)
	}
	if len(body) > maxResponseBytes {
		return fmt.Errorf("%w: LRCLIB answer is too large", ErrUnavailable)
	}
	if err := json.Unmarshal(body, out); err != nil {
		return fmt.Errorf("%w: invalid LRCLIB answer: %v", ErrUnavailable, err)
	}
	return nil
}

// intervalLimiter spaces requests at least interval apart. A caller whose
// turn is more than maxWait away gets ErrUnavailable at once.
type intervalLimiter struct {
	mu       sync.Mutex
	interval time.Duration
	maxWait  time.Duration
	next     time.Time
	now      func() time.Time
}

func (l *intervalLimiter) wait(ctx context.Context) error {
	l.mu.Lock()
	now := l.now()
	at := l.next
	if at.Before(now) {
		at = now
	}
	delay := at.Sub(now)
	if delay > l.maxWait {
		l.mu.Unlock()
		return fmt.Errorf("%w: too many lyrics lookups", ErrUnavailable)
	}
	l.next = at.Add(l.interval)
	l.mu.Unlock()
	if delay <= 0 {
		return nil
	}
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}
