package linkimport

import (
	"errors"
	"net/url"
	"regexp"
	"strings"
)

// More reasons a link is refused.
var (
	// ErrTooLong means the video is longer than imports allow.
	ErrTooLong = errors.New("the media is longer than allowed")
	// ErrMetadataOnly means the link is a Spotify one: its audio can't be
	// downloaded, only matched against the library.
	ErrMetadataOnly = errors.New("the link only has metadata to import")
)

// Sites whose links are handled by their own importer rather than by
// searching a page for audio files.
const (
	SiteYouTube   = "youtube"
	SiteInstagram = "instagram"
	SiteSpotify   = "spotify"
)

// SocialLink is a recognised link to one video, post or Spotify item,
// rebuilt from its ID: nothing else the user typed reaches yt-dlp or a fetch.
type SocialLink struct {
	Site string
	// Kind is "video" for YouTube and Instagram, or Spotify's "track",
	// "album" or "playlist".
	Kind string
	ID   string
	// URL is the canonical link.
	URL *url.URL
}

var (
	youTubeID   = regexp.MustCompile(`^[A-Za-z0-9_-]{11}$`)
	instagramID = regexp.MustCompile(`^[A-Za-z0-9_-]{5,64}$`)
	spotifyID   = regexp.MustCompile(`^[A-Za-z0-9]{22}$`)
	spotifyIntl = regexp.MustCompile(`^intl-[a-z]{2}(?:-[a-z]{2})?$`)
)

var (
	youTubeHosts   = map[string]bool{"youtube.com": true, "www.youtube.com": true, "m.youtube.com": true, "music.youtube.com": true}
	instagramHosts = map[string]bool{"instagram.com": true, "www.instagram.com": true, "m.instagram.com": true}
)

// DetectSocial recognises YouTube, Instagram and Spotify links by their exact
// host. ok is false for any other site. A link on one of these sites that
// isn't a single video, post or Spotify track, album or playlist is
// ErrUnsupported, so it never falls through to the page search.
func DetectSocial(u *url.URL) (link SocialLink, ok bool, err error) {
	host := strings.TrimSuffix(strings.ToLower(u.Hostname()), ".")
	port := u.Port()
	var site string
	switch {
	case youTubeHosts[host] || host == "youtu.be":
		site = SiteYouTube
	case instagramHosts[host]:
		site = SiteInstagram
	case host == "open.spotify.com":
		site = SiteSpotify
	default:
		return SocialLink{}, false, nil
	}
	if port != "" && port != "443" && port != "80" {
		return SocialLink{}, true, ErrUnsupported
	}
	segments := pathSegments(u.Path)
	switch site {
	case SiteYouTube:
		id := ""
		switch {
		case host == "youtu.be" && len(segments) == 1:
			id = segments[0]
		case len(segments) == 1 && segments[0] == "watch":
			id = u.Query().Get("v")
		case len(segments) == 2 && (segments[0] == "shorts" || segments[0] == "embed" || segments[0] == "live"):
			id = segments[1]
		}
		if !youTubeID.MatchString(id) {
			return SocialLink{}, true, ErrUnsupported
		}
		return SocialLink{Site: site, Kind: "video", ID: id, URL: &url.URL{
			Scheme: "https", Host: "www.youtube.com", Path: "/watch", RawQuery: url.Values{"v": {id}}.Encode(),
		}}, true, nil
	case SiteInstagram:
		// /reel/CODE, /reels/CODE, /p/CODE, /tv/CODE, optionally after a
		// user name.
		if len(segments) == 3 {
			segments = segments[1:]
		}
		if len(segments) != 2 || !instagramID.MatchString(segments[1]) {
			return SocialLink{}, true, ErrUnsupported
		}
		kind := map[string]string{"reel": "reel", "reels": "reel", "p": "p", "tv": "tv"}[segments[0]]
		if kind == "" {
			return SocialLink{}, true, ErrUnsupported
		}
		return SocialLink{Site: site, Kind: "video", ID: segments[1], URL: &url.URL{
			Scheme: "https", Host: "www.instagram.com", Path: "/" + kind + "/" + segments[1] + "/",
		}}, true, nil
	default:
		if len(segments) == 3 && spotifyIntl.MatchString(segments[0]) {
			segments = segments[1:]
		}
		if len(segments) != 2 || !spotifyID.MatchString(segments[1]) {
			return SocialLink{}, true, ErrUnsupported
		}
		switch segments[0] {
		case "track", "album", "playlist":
		default:
			return SocialLink{}, true, ErrUnsupported
		}
		return SocialLink{Site: site, Kind: segments[0], ID: segments[1], URL: &url.URL{
			Scheme: "https", Host: "open.spotify.com", Path: "/" + segments[0] + "/" + segments[1],
		}}, true, nil
	}
}

func pathSegments(p string) []string {
	var segments []string
	for _, s := range strings.Split(p, "/") {
		if s != "" {
			segments = append(segments, s)
		}
	}
	return segments
}
