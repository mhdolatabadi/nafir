package storage

import (
	"context"
	"net/url"
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
