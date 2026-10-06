package audio

import (
	"errors"
	"fmt"
	"path"
	"strings"
	"unicode"
	"unicode/utf8"
)

const (
	// MaxFileNameRunes keeps a display file name readable in the app.
	MaxFileNameRunes = 200
	// maxFileNameBytes is the common file system limit for one path element,
	// so a downloaded file can always be saved under its edited name.
	maxFileNameBytes = 255
)

// Reasons a display file name is rejected.
var (
	ErrFileNameEmpty     = errors.New("file name is empty")
	ErrFileNameTooLong   = errors.New("file name is too long")
	ErrFileNameUnsafe    = errors.New("file name contains unsafe characters")
	ErrFileNameExtension = errors.New("file name extension cannot change")
)

// unsafeFileNameRunes cannot appear in a file name on at least one of the
// file systems Web and Android users save to.
const unsafeFileNameRunes = `/\<>:"|?*`

// ValidFileName checks a display file name chosen by the user for a track
// whose current name is current. Unicode, including Persian, is kept; path
// separators, control and bidirectional override characters (which can
// disguise the real extension), and names that only some file systems allow
// are rejected rather than silently rewritten. The extension must stay the
// same as current's, ignoring case, and is returned exactly as current spells
// it, so the stored format and the name always agree.
func ValidFileName(name, current string) (string, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", ErrFileNameEmpty
	}
	if !utf8.ValidString(name) {
		return "", ErrFileNameUnsafe
	}
	for _, r := range name {
		if unsafeFileNameRune(r) {
			return "", ErrFileNameUnsafe
		}
	}
	if strings.HasPrefix(name, ".") || strings.HasSuffix(name, ".") {
		return "", ErrFileNameUnsafe
	}
	ext := path.Ext(name)
	currentExt := path.Ext(current)
	if currentExt == "" || !strings.EqualFold(ext, currentExt) {
		return "", ErrFileNameExtension
	}
	stem := strings.TrimSpace(strings.TrimSuffix(name, ext))
	if stem == "" || strings.HasSuffix(stem, ".") {
		return "", ErrFileNameEmpty
	}
	name = stem + currentExt
	if utf8.RuneCountInString(name) > MaxFileNameRunes || len(name) > maxFileNameBytes {
		return "", ErrFileNameTooLong
	}
	return name, nil
}

// DisplayFileName turns a client-supplied upload name into the display file
// name stored with the track. Unlike SafeFileName it keeps Unicode, replacing
// only what ValidFileName would reject.
func DisplayFileName(name string) string {
	name = path.Base(strings.ReplaceAll(name, "\\", "/"))
	if name == "." || name == "/" {
		name = ""
	}
	ext := strings.ToLower(path.Ext(name))
	stem := strings.Map(func(r rune) rune {
		if unsafeFileNameRune(r) {
			return '_'
		}
		return r
	}, strings.TrimSuffix(name, path.Ext(name)))
	stem = strings.Trim(stem, " ._")
	for stem != "" && (utf8.RuneCountInString(stem)+len(ext) > MaxFileNameRunes || len(stem)+len(ext) > maxFileNameBytes) {
		_, size := utf8.DecodeLastRuneInString(stem)
		stem = strings.TrimRight(stem[:len(stem)-size], " .")
	}
	if stem == "" {
		stem = "track"
	}
	return stem + ext
}

func unsafeFileNameRune(r rune) bool {
	if r == utf8.RuneError || unicode.IsControl(r) || strings.ContainsRune(unsafeFileNameRunes, r) {
		return true
	}
	switch {
	case r >= 0x202A && r <= 0x202E: // LRE, RLE, PDF, LRO, RLO
		return true
	case r >= 0x2066 && r <= 0x2069: // LRI, RLI, FSI, PDI
		return true
	}
	return false
}

// ContentDisposition is an RFC 6266 attachment header for a download saved as
// name: a quoted ASCII fallback for old clients plus the exact UTF-8 name as
// an RFC 5987 filename* parameter, which current browsers prefer.
func ContentDisposition(name string) string {
	ext := path.Ext(name)
	fallback := strings.Map(func(r rune) rune {
		if r < 0x20 || r >= 0x7F || r == '"' || r == '\\' || r == '%' || unsafeFileNameRune(r) {
			return '_'
		}
		return r
	}, strings.TrimSuffix(name, ext))
	if strings.Trim(fallback, "_ ") == "" {
		fallback = "track"
	}
	fallback += strings.Map(func(r rune) rune {
		if r < 0x20 || r >= 0x7F || r == '"' || r == '\\' {
			return -1
		}
		return r
	}, ext)
	var encoded strings.Builder
	for _, b := range []byte(name) {
		if isAttrChar(b) {
			encoded.WriteByte(b)
		} else {
			fmt.Fprintf(&encoded, "%%%02X", b)
		}
	}
	return `attachment; filename="` + fallback + `"; filename*=UTF-8''` + encoded.String()
}

// isAttrChar reports whether RFC 5987 allows b unencoded in a value.
func isAttrChar(b byte) bool {
	switch {
	case b >= 'a' && b <= 'z', b >= 'A' && b <= 'Z', b >= '0' && b <= '9':
		return true
	}
	return strings.IndexByte("!#$&+-.^_`|~", b) >= 0
}
