// Package linkimport adds music to a library from a link: a song page on a
// music site, or the audio file itself. Pages and files are fetched with a
// client that can only reach public addresses, then the download runs as
// an ordinary import job.
package linkimport

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"strings"
	"syscall"
	"time"
)

// Errors a link can be refused with, each with its own message in the app.
var (
	ErrInvalidURL  = errors.New("not an http or https link")
	ErrBlocked     = errors.New("the link points to an address that is not allowed")
	ErrUnreachable = errors.New("the page could not be fetched")
	ErrNoAudio     = errors.New("no audio file was found on the page")
	ErrUnsupported = errors.New("the link is not a supported audio file or page")
	ErrTooLarge    = errors.New("the file is larger than allowed")
)

const (
	maxURLLength  = 2048
	maxRedirects  = 5
	maxPageBytes  = 2 << 20
	pageTimeout   = 20 * time.Second
	headerTimeout = 20 * time.Second
	userAgent     = "Mozilla/5.0 (compatible; NafirImporter/1.0)"
)

// blockedPrefixes are non-public ranges that netip's own checks don't cover:
// shared address space, benchmarking, documentation, reserved, and IPv6
// transition ranges that can embed an internal IPv4 address.
var blockedPrefixes = func() []netip.Prefix {
	var prefixes []netip.Prefix
	for _, p := range []string{
		"0.0.0.0/8", "100.64.0.0/10", "192.0.0.0/24", "192.0.2.0/24", "198.18.0.0/15",
		"198.51.100.0/24", "203.0.113.0/24", "240.0.0.0/4",
		"64:ff9b::/96", "64:ff9b:1::/48", "2001:db8::/32", "2002::/16", "100::/64",
	} {
		prefixes = append(prefixes, netip.MustParsePrefix(p))
	}
	return prefixes
}()

// PublicAddress reports whether ip is a public unicast address a fetch may
// connect to. Loopback, private, link-local (including cloud metadata at
// 169.254.169.254), multicast and reserved ranges are not.
func PublicAddress(ip netip.Addr) bool {
	ip = ip.Unmap()
	if !ip.IsValid() || !ip.IsGlobalUnicast() || ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() {
		return false
	}
	for _, p := range blockedPrefixes {
		if p.Contains(ip) {
			return false
		}
	}
	return true
}

// Fetcher makes requests that can only reach allowed addresses. The check
// runs on the address actually dialed, so it also covers every redirect and
// a name that resolves to an internal address.
type Fetcher struct {
	client *http.Client
}

// NewFetcher fetches from public addresses on the standard web ports.
func NewFetcher() *Fetcher {
	return newFetcher(PublicAddress, map[uint16]bool{80: true, 443: true})
}

func newFetcher(allowed func(netip.Addr) bool, ports map[uint16]bool) *Fetcher {
	dialer := &net.Dialer{
		Timeout: 10 * time.Second,
		Control: func(_, address string, _ syscall.RawConn) error {
			addrPort, err := netip.ParseAddrPort(address)
			if err != nil || !allowed(addrPort.Addr()) || !ports[addrPort.Port()] {
				return ErrBlocked
			}
			return nil
		},
	}
	transport := &http.Transport{
		// Never through a proxy: the address check must see the real target.
		Proxy:                  nil,
		DialContext:            dialer.DialContext,
		TLSHandshakeTimeout:    10 * time.Second,
		ResponseHeaderTimeout:  headerTimeout,
		MaxResponseHeaderBytes: 64 << 10,
		// Keeps Content-Length meaningful for audio downloads.
		DisableCompression: true,
		MaxIdleConns:       10,
		IdleConnTimeout:    30 * time.Second,
	}
	return &Fetcher{client: &http.Client{
		Transport: transport,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= maxRedirects {
				return fmt.Errorf("%w: too many redirects", ErrUnreachable)
			}
			if _, err := checkURL(req.URL); err != nil {
				return err
			}
			return nil
		},
	}}
}

// ParseURL accepts an absolute http or https link without credentials.
func ParseURL(raw string) (*url.URL, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" || len(raw) > maxURLLength {
		return nil, ErrInvalidURL
	}
	u, err := url.Parse(raw)
	if err != nil {
		return nil, ErrInvalidURL
	}
	return checkURL(u)
}

func checkURL(u *url.URL) (*url.URL, error) {
	if (u.Scheme != "http" && u.Scheme != "https") || u.Hostname() == "" || u.User != nil {
		return nil, ErrInvalidURL
	}
	return u, nil
}

// get starts a GET request. A refused address is ErrBlocked; anything else
// that stops the response, or a status other than 200, is ErrUnreachable.
func (f *Fetcher) get(ctx context.Context, u *url.URL) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return nil, ErrInvalidURL
	}
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("Accept", "text/html,application/xhtml+xml,audio/*;q=0.9,*/*;q=0.8")
	resp, err := f.client.Do(req)
	switch {
	case errors.Is(err, ErrBlocked):
		return nil, ErrBlocked
	case errors.Is(err, ErrInvalidURL):
		return nil, ErrInvalidURL
	case err != nil:
		// Keep the link out of the error: it may be private, and import
		// failures are logged.
		var urlErr *url.Error
		if errors.As(err, &urlErr) {
			err = urlErr.Err
		}
		return nil, fmt.Errorf("%w: %v", ErrUnreachable, err)
	}
	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return nil, fmt.Errorf("%w: status %d", ErrUnreachable, resp.StatusCode)
	}
	return resp, nil
}
