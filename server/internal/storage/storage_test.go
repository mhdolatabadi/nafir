package storage

import (
	"context"
	"encoding/base64"
	"net/url"
	"strings"
	"testing"
	"time"
)

func newTestStorage(t *testing.T, ttl time.Duration) *Storage {
	t.Helper()
	s, err := New(Config{
		Endpoint:  "minio:9000",
		PublicURL: "https://music.example.com",
		AccessKey: "access",
		SecretKey: "secret-secret",
		Bucket:    "nafir-music",
		URLTTL:    ttl,
	})
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestPresignGetSignsForThePublicOrigin(t *testing.T) {
	s := newTestStorage(t, 15*time.Minute)

	signed, expiresAt, err := s.PresignGet(context.Background(), "users/u1/tracks/t1/song.mp3")
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := url.Parse(signed)
	if err != nil {
		t.Fatal(err)
	}
	if parsed.Scheme != "https" || parsed.Host != "music.example.com" {
		t.Fatalf("URL is not on the public origin: %s", signed)
	}
	if parsed.Path != "/nafir-music/users/u1/tracks/t1/song.mp3" {
		t.Fatalf("unexpected path %q", parsed.Path)
	}
	query := parsed.Query()
	if query.Get("X-Amz-Expires") != "900" || query.Get("X-Amz-Signature") == "" {
		t.Fatalf("URL is not a 15 minute presigned URL: %s", signed)
	}
	if remaining := time.Until(expiresAt); remaining <= 14*time.Minute || remaining > 15*time.Minute {
		t.Fatalf("unexpected expiry %v", expiresAt)
	}
}

func TestPresignDownloadAsksForAnAttachment(t *testing.T) {
	s := newTestStorage(t, 15*time.Minute)

	signed, _, err := s.PresignDownload(context.Background(), "users/u1/tracks/t1/song.mp3", "My_Song.mp3")
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := url.Parse(signed)
	if err != nil {
		t.Fatal(err)
	}
	query := parsed.Query()
	if query.Get("response-content-disposition") != `attachment; filename="My_Song.mp3"; filename*=UTF-8''My_Song.mp3` ||
		query.Get("X-Amz-Signature") == "" {
		t.Fatalf("download URL is not a signed attachment: %s", signed)
	}
}

func TestAttachmentDisposition(t *testing.T) {
	for in, want := range map[string]string{
		"song.mp3":        `attachment; filename="song.mp3"; filename*=UTF-8''song.mp3`,
		"a\"b\\c.mp3":     `attachment; filename="a_b_c.mp3"; filename*=UTF-8''a%22b%5Cc.mp3`,
		"آهنگ.mp3":        `attachment; filename="____.mp3"; filename*=UTF-8''%D8%A2%D9%87%D9%86%DA%AF.mp3`,
		"..":              `attachment; filename="track"; filename*=UTF-8''..`,
		"a b=c@d.mp3":     `attachment; filename="a b=c@d.mp3"; filename*=UTF-8''a%20b%3Dc%40d.mp3`,
		"line\nbreak.mp3": `attachment; filename="line_break.mp3"; filename*=UTF-8''line%0Abreak.mp3`,
	} {
		if got := AttachmentDisposition(in); got != want {
			t.Errorf("AttachmentDisposition(%q) = %s, want %s", in, got, want)
		}
	}
}

func TestNewRejectsBadConfig(t *testing.T) {
	base := Config{
		Endpoint: "minio:9000", PublicURL: "https://music.example.com",
		AccessKey: "a", SecretKey: "s", Bucket: "b", URLTTL: time.Hour,
	}
	for name, mutate := range map[string]func(*Config){
		"no bucket":       func(c *Config) { c.Bucket = "" },
		"no secret":       func(c *Config) { c.SecretKey = "" },
		"zero ttl":        func(c *Config) { c.URLTTL = 0 },
		"ttl over 7 days": func(c *Config) { c.URLTTL = 8 * 24 * time.Hour },
		"relative url":    func(c *Config) { c.PublicURL = "music.example.com" },
	} {
		t.Run(name, func(t *testing.T) {
			config := base
			mutate(&config)
			if _, err := New(config); err == nil {
				t.Fatal("expected an error")
			}
		})
	}
}

func TestPresignUploadPinsKeyTypeAndSize(t *testing.T) {
	s := newTestStorage(t, time.Hour)

	upload, err := s.PresignUpload(context.Background(), "users/u1/tracks/t1/song.mp3", "audio/mpeg", 1234)
	if err != nil {
		t.Fatal(err)
	}
	if upload.URL != "https://music.example.com/nafir-music/" {
		t.Fatalf("unexpected upload URL %q", upload.URL)
	}
	if upload.Fields["key"] != "users/u1/tracks/t1/song.mp3" || upload.Fields["Content-Type"] != "audio/mpeg" {
		t.Fatalf("unexpected fields %v", upload.Fields)
	}
	if upload.Fields["policy"] == "" || upload.Fields["x-amz-signature"] == "" {
		t.Fatalf("form is not signed: %v", upload.Fields)
	}
	policy, err := base64.StdEncoding.DecodeString(upload.Fields["policy"])
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(policy), `["content-length-range", 1234, 1234]`) {
		t.Fatalf("policy does not pin the size: %s", policy)
	}
	if !upload.ExpiresAt.After(time.Now()) {
		t.Fatalf("upload already expired: %v", upload.ExpiresAt)
	}
}
