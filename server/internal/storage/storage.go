// Package storage keeps audio in a private MinIO bucket and hands out
// short-lived presigned URLs for it.
package storage

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

// region is fixed so presigning never has to ask MinIO for the bucket location.
const region = "us-east-1"

type Config struct {
	// Endpoint is the internal host:port the API uses, for example minio:9000.
	Endpoint string
	// PublicURL is the origin clients reach MinIO through, for example
	// https://music.example.com. URLs are signed for this host.
	PublicURL string
	AccessKey string
	SecretKey string
	Bucket    string
	URLTTL    time.Duration
}

type Storage struct {
	internal *minio.Client
	public   *minio.Client
	bucket   string
	ttl      time.Duration
	now      func() time.Time
}

func New(config Config) (*Storage, error) {
	if config.Bucket == "" || config.AccessKey == "" || config.SecretKey == "" {
		return nil, errors.New("storage bucket and credentials are required")
	}
	if config.URLTTL <= 0 || config.URLTTL > 7*24*time.Hour {
		return nil, errors.New("storage URL lifetime must be between 0 and 7 days")
	}
	creds := credentials.NewStaticV4(config.AccessKey, config.SecretKey, "")

	internal, err := minio.New(config.Endpoint, &minio.Options{Creds: creds, Region: region})
	if err != nil {
		return nil, fmt.Errorf("internal endpoint: %w", err)
	}
	publicURL, err := url.Parse(config.PublicURL)
	if err != nil || publicURL.Host == "" || (publicURL.Scheme != "https" && publicURL.Scheme != "http") {
		return nil, fmt.Errorf("public URL %q must be an http(s) origin", config.PublicURL)
	}
	public, err := minio.New(publicURL.Host, &minio.Options{
		Creds:  creds,
		Secure: publicURL.Scheme == "https",
		Region: region,
	})
	if err != nil {
		return nil, fmt.Errorf("public endpoint: %w", err)
	}
	return &Storage{internal: internal, public: public, bucket: config.Bucket, ttl: config.URLTTL, now: time.Now}, nil
}

// EnsureBucket creates the bucket if needed. New buckets in MinIO are private;
// no anonymous policy is ever attached.
func (s *Storage) EnsureBucket(ctx context.Context) error {
	exists, err := s.internal.BucketExists(ctx, s.bucket)
	if err != nil {
		return err
	}
	if exists {
		return nil
	}
	return s.internal.MakeBucket(ctx, s.bucket, minio.MakeBucketOptions{Region: region})
}

// PresignGet returns a URL that allows reading key until the returned time.
func (s *Storage) PresignGet(ctx context.Context, key string) (string, time.Time, error) {
	expiresAt := s.now().Add(s.ttl)
	signed, err := s.public.PresignedGetObject(ctx, s.bucket, key, s.ttl, url.Values{})
	if err != nil {
		return "", time.Time{}, err
	}
	return signed.String(), expiresAt, nil
}
