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

func TestPresignDownloadSignsTheSaveAsHeaders(t *testing.T) {
	s := newTestStorage(t, 15*time.Minute)
	disposition := `attachment; filename="track.mp3"; filename*=UTF-8''%D8%A2.mp3`
	signed, _, err := s.PresignDownload(context.Background(), "users/u1/tracks/t1/v2-1/track.mp3", disposition, "audio/mpeg")
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := url.Parse(signed)
	if err != nil {
		t.Fatal(err)
	}
	query := parsed.Query()
	if query.Get("response-content-disposition") != disposition || query.Get("response-content-type") != "audio/mpeg" ||
		query.Get("response-cache-control") != "private, no-cache" || query.Get("X-Amz-Signature") == "" {
		t.Fatalf("download URL does not carry the signed headers: %s", signed)
	}
}

func TestAllowsAnonymous(t *testing.T) {
	for _, tc := range []struct {
		policy string
		public bool
	}{
		{"", false},
		{"  ", false},
		// What `mc anonymous set download` writes.
		{`{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":["*"]},"Action":["s3:GetObject"],"Resource":["arn:aws:s3:::nafir-music/*"]}]}`, true},
		{`{"Statement":[{"Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"*"}]}`, true},
		{`{"Statement":[{"Effect":"Allow","Principal":{"AWS":"*"},"Action":"s3:PutObject","Resource":"*"}]}`, true},
		{`{"Statement":[{"Effect":"Deny","Principal":"*","Action":"s3:*","Resource":"*"}]}`, false},
		{`{"Statement":[{"Effect":"Allow","Principal":{"AWS":["arn:aws:iam::123:user/api"]},"Action":"s3:GetObject","Resource":"*"}]}`, false},
	} {
		public, err := allowsAnonymous(tc.policy)
		if err != nil || public != tc.public {
			t.Errorf("allowsAnonymous(%s) = %v, %v; want %v", tc.policy, public, err, tc.public)
		}
	}
	if _, err := allowsAnonymous("{not json"); err == nil {
		t.Error("a malformed policy must be an error")
	}
}
