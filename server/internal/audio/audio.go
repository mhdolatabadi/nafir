// Package audio decides which uploads are accepted as music files.
package audio

import (
	"bytes"
	"path"
	"strings"
	"unicode"
)

// HeaderBytes is how much of an object Matches needs to look at.
const HeaderBytes = 16

type format struct {
	contentType string
	matches     func(header []byte) bool
}

var formats = map[string]format{
	".mp3":  {"audio/mpeg", isMP3},
	".m4a":  {"audio/mp4", isMP4},
	".aac":  {"audio/aac", isADTS},
	".flac": {"audio/flac", prefix("fLaC")},
	".ogg":  {"audio/ogg", prefix("OggS")},
	".opus": {"audio/ogg", prefix("OggS")},
	".wav":  {"audio/wav", isWAV},
	".webm": {"audio/webm", prefix("\x1a\x45\xdf\xa3")},
}

// Extensions lists the accepted file extensions without the dot.
func Extensions() []string {
	extensions := make([]string, 0, len(formats))
	for ext := range formats {
		extensions = append(extensions, strings.TrimPrefix(ext, "."))
	}
	return extensions
}

// ContentType returns the content type for an accepted file name.
func ContentType(fileName string) (string, bool) {
	f, ok := formats[strings.ToLower(path.Ext(fileName))]
	return f.contentType, ok
}

// Matches reports whether the first bytes of a file look like its extension says.
func Matches(fileName string, header []byte) bool {
	f, ok := formats[strings.ToLower(path.Ext(fileName))]
	return ok && f.matches(header)
}

// SafeFileName reduces a client-supplied name to a short ASCII object name
// that keeps the extension, for example "آهنگ من.MP3" -> "track.mp3".
func SafeFileName(name string) string {
	name = path.Base(strings.ReplaceAll(name, "\\", "/"))
	if name == "." || name == "/" {
		name = ""
	}
	ext := strings.ToLower(path.Ext(name))
	stem := strings.Map(func(r rune) rune {
		if r < unicode.MaxASCII && (unicode.IsLetter(r) || unicode.IsDigit(r) || r == '-' || r == '_') {
			return r
		}
		return '_'
	}, strings.TrimSuffix(name, path.Ext(name)))
	stem = strings.Trim(stem, "_")
	if len(stem) > 80 {
		stem = stem[:80]
	}
	if stem == "" {
		stem = "track"
	}
	return stem + ext
}

// Title derives a display title from a file name when none is given.
func Title(fileName string) string {
	base := path.Base(strings.ReplaceAll(fileName, "\\", "/"))
	title := strings.TrimSpace(strings.TrimSuffix(base, path.Ext(base)))
	if title == "" {
		return "Untitled"
	}
	return title
}

func prefix(p string) func([]byte) bool {
	return func(h []byte) bool { return bytes.HasPrefix(h, []byte(p)) }
}

func isMP3(h []byte) bool {
	return bytes.HasPrefix(h, []byte("ID3")) || (len(h) >= 2 && h[0] == 0xFF && h[1]&0xE0 == 0xE0)
}

func isADTS(h []byte) bool {
	return len(h) >= 2 && h[0] == 0xFF && h[1]&0xF6 == 0xF0
}

func isMP4(h []byte) bool {
	return len(h) >= 8 && string(h[4:8]) == "ftyp"
}

func isWAV(h []byte) bool {
	return len(h) >= 12 && string(h[0:4]) == "RIFF" && string(h[8:12]) == "WAVE"
}
