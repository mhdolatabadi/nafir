package audio

import (
	"errors"
	"path"
	"strings"
	"testing"
)

func TestContentType(t *testing.T) {
	for name, want := range map[string]string{
		"song.mp3": "audio/mpeg", "SONG.M4A": "audio/mp4", "a.flac": "audio/flac", "b.opus": "audio/ogg",
	} {
		if got, ok := ContentType(name); !ok || got != want {
			t.Errorf("ContentType(%q) = %q, %v; want %q", name, got, ok, want)
		}
	}
	for _, name := range []string{"notes.txt", "song", "song.mp3.exe"} {
		if _, ok := ContentType(name); ok {
			t.Errorf("ContentType(%q) should be rejected", name)
		}
	}
}

func TestMatches(t *testing.T) {
	cases := []struct {
		name   string
		header string
		want   bool
	}{
		{"a.mp3", "ID3\x04\x00", true},
		{"a.mp3", "\xff\xfb\x90\x00", true},
		{"a.m4a", "\x00\x00\x00\x20ftypM4A ", true},
		{"a.aac", "\xff\xf1\x50\x80", true},
		{"a.flac", "fLaC\x00\x00", true},
		{"a.ogg", "OggS\x00\x02", true},
		{"a.wav", "RIFF\x24\x00\x00\x00WAVEfmt ", true},
		{"a.webm", "\x1a\x45\xdf\xa3\x01", true},
		{"a.mp3", "<html><body>", false},
		{"a.flac", "OggS\x00\x02", false},
		{"a.wav", "RIFF\x24\x00\x00\x00AVI ", false},
		{"a.txt", "ID3", false},
		{"a.mp3", "", false},
	}
	for _, tc := range cases {
		if got := Matches(tc.name, []byte(tc.header)); got != tc.want {
			t.Errorf("Matches(%q, %q) = %v, want %v", tc.name, tc.header, got, tc.want)
		}
	}
}

func TestSafeFileName(t *testing.T) {
	for in, want := range map[string]string{
		"My Song.MP3":          "My_Song.mp3",
		"آهنگ من.mp3":          "track.mp3",
		"../../etc/passwd.mp3": "passwd.mp3",
		`C:\Music\a b.flac`:    "a_b.flac",
		"":                     "track",
	} {
		if got := SafeFileName(in); got != want {
			t.Errorf("SafeFileName(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestTitle(t *testing.T) {
	if got := Title("آهنگ من.mp3"); got != "آهنگ من" {
		t.Errorf("Title = %q", got)
	}
	if got := Title(".mp3"); got != "Untitled" {
		t.Errorf("Title = %q", got)
	}
}

func TestValidFileName(t *testing.T) {
	for _, tc := range []struct{ in, current, want string }{
		{" آهنگ من.mp3 ", "track.mp3", "آهنگ من.mp3"},
		{"New Name.MP3", "old.mp3", "New Name.mp3"},
		{"می‌خواهم.flac", "a.FLAC", "می‌خواهم.FLAC"},
		{"Track 01 - Intro.ogg", "x.ogg", "Track 01 - Intro.ogg"},
	} {
		got, err := ValidFileName(tc.in, tc.current)
		if err != nil || got != tc.want {
			t.Errorf("ValidFileName(%q, %q) = %q, %v; want %q", tc.in, tc.current, got, err, tc.want)
		}
	}
	for _, tc := range []struct {
		in, current string
		want        error
	}{
		{"", "a.mp3", ErrFileNameEmpty},
		{"   ", "a.mp3", ErrFileNameEmpty},
		{".mp3", "a.mp3", ErrFileNameUnsafe},
		{" .mp3", "a.mp3", ErrFileNameUnsafe},
		{"..mp3", "a.mp3", ErrFileNameUnsafe},
		{"a..mp3", "a.mp3", ErrFileNameEmpty},
		{"../../etc/passwd.mp3", "a.mp3", ErrFileNameUnsafe},
		{`..\secret.mp3`, "a.mp3", ErrFileNameUnsafe},
		{"song.flac", "a.mp3", ErrFileNameExtension},
		{"song", "a.mp3", ErrFileNameExtension},
		{"song.mp3.exe", "a.mp3", ErrFileNameExtension},
		{"song.mp3", "noext", ErrFileNameExtension},
		{"evil\u202Egpj.mp3", "a.mp3", ErrFileNameUnsafe},
		{"evil\u2067x.mp3", "a.mp3", ErrFileNameUnsafe},
		{"line\nbreak.mp3", "a.mp3", ErrFileNameUnsafe},
		{"nul\x00.mp3", "a.mp3", ErrFileNameUnsafe},
		{`quote".mp3`, "a.mp3", ErrFileNameUnsafe},
		{"what?.mp3", "a.mp3", ErrFileNameUnsafe},
		{"bad\xff.mp3", "a.mp3", ErrFileNameUnsafe},
		{strings.Repeat("x", 197) + ".mp3", "a.mp3", ErrFileNameTooLong},
		{strings.Repeat("آ", 130) + ".mp3", "a.mp3", ErrFileNameTooLong}, // 264 bytes
	} {
		if _, err := ValidFileName(tc.in, tc.current); !errors.Is(err, tc.want) {
			t.Errorf("ValidFileName(%q, %q) error = %v, want %v", tc.in, tc.current, err, tc.want)
		}
	}
}

func TestDisplayFileName(t *testing.T) {
	for in, want := range map[string]string{
		"آهنگ من.MP3":            "آهنگ من.mp3",
		"../../etc/passwd.mp3":   "passwd.mp3",
		`C:\Music\a b.flac`:      "a b.flac",
		"what?\u202E.mp3":        "what.mp3",
		".mp3":                   "track.mp3",
		"":                       "track",
		strings.Repeat("ب", 300): strings.Repeat("ب", 127),
	} {
		got := DisplayFileName(in)
		if got != want {
			t.Errorf("DisplayFileName(%q) = %q, want %q", in, got, want)
		}
		if got != "track" {
			if _, err := ValidFileName(got, "x"+path.Ext(got)); err != nil && path.Ext(got) != "" {
				t.Errorf("DisplayFileName(%q) = %q is not a valid file name: %v", in, got, err)
			}
		}
	}
}

func TestContentDisposition(t *testing.T) {
	for in, want := range map[string]string{
		"song.mp3":            `attachment; filename="song.mp3"; filename*=UTF-8''song.mp3`,
		"آهنگ من.mp3":         `attachment; filename="track.mp3"; filename*=UTF-8''%D8%A2%D9%87%D9%86%DA%AF%20%D9%85%D9%86.mp3`,
		`My "Best" Song.flac`: `attachment; filename="My _Best_ Song.flac"; filename*=UTF-8''My%20%22Best%22%20Song.flac`,
		"Mix آهنگ.ogg":        `attachment; filename="Mix ____.ogg"; filename*=UTF-8''Mix%20%D8%A2%D9%87%D9%86%DA%AF.ogg`,
		"50% off;x.mp3":       `attachment; filename="50_ off;x.mp3"; filename*=UTF-8''50%25%20off%3Bx.mp3`,
	} {
		if got := ContentDisposition(in); got != want {
			t.Errorf("ContentDisposition(%q)\n got %s\nwant %s", in, got, want)
		}
	}
	// Whatever the name, the header stays one line of printable ASCII.
	for _, name := range []string{"a\r\nSet-Cookie: x.mp3", "‮gpj.mp3", strings.Repeat("ب", 200) + ".mp3"} {
		got := ContentDisposition(name)
		for _, r := range got {
			if r < 0x20 || r >= 0x7F {
				t.Fatalf("ContentDisposition(%q) has %q", name, r)
			}
		}
	}
}
