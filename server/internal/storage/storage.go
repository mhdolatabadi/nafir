// Package storage keeps audio in a private MinIO bucket and hands out
// short-lived presigned URLs for it.
package storage

import (
	"context"
	"errors"
	"fmt"
	"io"
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
	// UploadTTL is how long a client has to start an upload.
	UploadTTL time.Duration
}

type Storage struct {
	internal  *minio.Client
	public    *minio.Client
	bucket    string
	ttl       time.Duration
	uploadTTL time.Duration
	now       func() time.Time
}

// ErrObjectMissing means nothing has been uploaded at the key yet.
var ErrObjectMissing = errors.New("object not found")

// Upload is a presigned POST form: the client sends Fields plus the file
// (as the last form field, named "file") to URL.
type Upload struct {
	URL       string
	Fields    map[string]string
	ExpiresAt time.Time
}

func New(config Config) (*Storage, error) {
	if config.Bucket == "" || config.AccessKey == "" || config.SecretKey == "" {
		return nil, errors.New("storage bucket and credentials are required")
	}
	if config.URLTTL <= 0 || config.URLTTL > 7*24*time.Hour {
		return nil, errors.New("storage URL lifetime must be between 0 and 7 days")
	}
	if config.UploadTTL == 0 {
		config.UploadTTL = time.Hour
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
	return &Storage{
		internal: internal, public: public, bucket: config.Bucket,
		ttl: config.URLTTL, uploadTTL: config.UploadTTL, now: time.Now,
	}, nil
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

// PresignUpload returns a POST policy that MinIO itself enforces: only this
// key, only this content type, and exactly sizeBytes bytes.
func (s *Storage) PresignUpload(ctx context.Context, key, contentType string, sizeBytes int64) (Upload, error) {
	expiresAt := s.now().Add(s.uploadTTL)
	policy := minio.NewPostPolicy()
	for _, err := range []error{
		policy.SetBucket(s.bucket),
		policy.SetKey(key),
		policy.SetContentType(contentType),
		policy.SetContentLengthRange(sizeBytes, sizeBytes),
		policy.SetExpires(expiresAt.UTC()),
	} {
		if err != nil {
			return Upload{}, err
		}
	}
	postURL, fields, err := s.public.PresignedPostPolicy(ctx, policy)
	if err != nil {
		return Upload{}, err
	}
	return Upload{URL: postURL.String(), Fields: fields, ExpiresAt: expiresAt}, nil
}

// Size returns the stored object's size.
func (s *Storage) Size(ctx context.Context, key string) (int64, error) {
	info, err := s.internal.StatObject(ctx, s.bucket, key, minio.StatObjectOptions{})
	if minio.ToErrorResponse(err).Code == "NoSuchKey" {
		return 0, ErrObjectMissing
	}
	if err != nil {
		return 0, err
	}
	return info.Size, nil
}

// Head returns up to n bytes from the start of the object.
func (s *Storage) Head(ctx context.Context, key string, n int64) ([]byte, error) {
	options := minio.GetObjectOptions{}
	if err := options.SetRange(0, n-1); err != nil {
		return nil, err
	}
	object, err := s.internal.GetObject(ctx, s.bucket, key, options)
	if err != nil {
		return nil, err
	}
	defer object.Close()
	return io.ReadAll(io.LimitReader(object, n))
}

// Remove deletes the object; a missing object is not an error.
func (s *Storage) Remove(ctx context.Context, key string) error {
	return s.internal.RemoveObject(ctx, s.bucket, key, minio.RemoveObjectOptions{})
}
