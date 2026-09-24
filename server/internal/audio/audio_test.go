package audio

import "testing"

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
