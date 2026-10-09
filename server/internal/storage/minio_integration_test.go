package storage

import (
	"bytes"
	"context"
	"errors"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

// These run against a real MinIO when STORAGE_TEST_ENDPOINT (host:port) is
// set, with STORAGE_TEST_ACCESS_KEY/SECRET_KEY being the API's limited user
// from deploy/minio-api-user.sh and STORAGE_TEST_ROOT_USER/ROOT_PASSWORD the
// admin account. They prove the limited user is enough for everything the
// API does (#217).
func minioFromEnv(t *testing.T) (*Storage, *minio.Client) {
	t.Helper()
	endpoint := os.Getenv("STORAGE_TEST_ENDPOINT")
	if endpoint == "" {
		t.Skip("STORAGE_TEST_ENDPOINT is not set")
	}
	objects, err := New(Config{
		Endpoint: endpoint, PublicURL: "http://" + endpoint,
		AccessKey: os.Getenv("STORAGE_TEST_ACCESS_KEY"), SecretKey: os.Getenv("STORAGE_TEST_SECRET_KEY"),
		Bucket: "nafir-music", URLTTL: time.Hour,
	})
	if err != nil {
		t.Fatal(err)
	}
	root, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(os.Getenv("STORAGE_TEST_ROOT_USER"), os.Getenv("STORAGE_TEST_ROOT_PASSWORD"), ""),
		Region: region,
	})
	if err != nil {
		t.Fatal(err)
	}
	return objects, root
}

func TestLimitedUserCoversEverythingTheAPIDoes(t *testing.T) {
	ctx := context.Background()
	objects, _ := minioFromEnv(t)
	if err := objects.EnsureBucket(ctx); err != nil {
		t.Fatalf("EnsureBucket: %v", err)
	}
	if err := objects.CheckPrivate(ctx); err != nil {
		t.Fatalf("CheckPrivate: %v", err)
	}

	// A browser upload through the presigned POST form.
	audio := append([]byte("ID3\x04\x00\x00\x00\x00\x00\x00"), bytes.Repeat([]byte{0xAB}, 4096)...)
	key := "users/u1/tracks/t1/song.mp3"
	form, err := objects.PresignUpload(ctx, key, "audio/mpeg", int64(len(audio)))
	if err != nil {
		t.Fatal(err)
	}
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	for name, value := range form.Fields {
		_ = writer.WriteField(name, value)
	}
	part, _ := writer.CreateFormFile("file", "song.mp3")
	_, _ = part.Write(audio)
	_ = writer.Close()
	response, err := http.Post(form.URL, writer.FormDataContentType(), &body)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode/100 != 2 {
		t.Fatalf("presigned upload: %d", response.StatusCode)
	}

	if size, err := objects.Size(ctx, key); err != nil || size != int64(len(audio)) {
		t.Fatalf("Size = %d, %v", size, err)
	}
	if head, err := objects.Head(ctx, key, 3); err != nil || string(head) != "ID3" {
		t.Fatalf("Head = %q, %v", head, err)
	}
	// Streaming through a presigned GET returns the stored bytes exactly.
	url, _, err := objects.PresignGet(ctx, key)
	if err != nil {
		t.Fatal(err)
	}
	got, err := http.Get(url)
	if err != nil {
		t.Fatal(err)
	}
	streamed, _ := io.ReadAll(got.Body)
	got.Body.Close()
	if !bytes.Equal(streamed, audio) {
		t.Fatalf("streamed %d bytes, stored %d; not identical", len(streamed), len(audio))
	}
	copyKey := "users/u1/tracks/t1/song.r2.mp3"
	if err := objects.Copy(ctx, key, copyKey); err != nil {
		t.Fatalf("Copy: %v", err)
	}
	if err := objects.Put(ctx, "users/u1/tracks/t2/x.mp3", bytes.NewReader(audio), int64(len(audio)), "audio/mpeg"); err != nil {
		t.Fatalf("Put: %v", err)
	}
	if err := objects.Remove(ctx, copyKey); err != nil {
		t.Fatalf("Remove: %v", err)
	}
	if removed, err := objects.RemovePrefix(ctx, "users/u1/"); err != nil || removed != 2 {
		t.Fatalf("RemovePrefix = %d, %v", removed, err)
	}
	if _, err := objects.Size(ctx, key); !errors.Is(err, ErrObjectMissing) {
		t.Fatalf("after RemovePrefix: %v", err)
	}

	// Anonymous clients get nothing.
	anonymous, err := http.Get("http://" + os.Getenv("STORAGE_TEST_ENDPOINT") + "/nafir-music/")
	if err != nil {
		t.Fatal(err)
	}
	anonymous.Body.Close()
	if anonymous.StatusCode != http.StatusForbidden {
		t.Fatalf("anonymous listing = %d", anonymous.StatusCode)
	}
}

func TestCheckPrivateNoticesAPublicBucket(t *testing.T) {
	ctx := context.Background()
	objects, root := minioFromEnv(t)
	if err := objects.EnsureBucket(ctx); err != nil {
		t.Fatal(err)
	}
	public := `{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":["*"]},"Action":["s3:GetObject"],"Resource":["arn:aws:s3:::nafir-music/*"]}]}`
	if err := root.SetBucketPolicy(ctx, "nafir-music", public); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = root.SetBucketPolicy(context.Background(), "nafir-music", "") })
	if err := objects.CheckPrivate(ctx); !errors.Is(err, ErrPublicBucket) {
		t.Fatalf("CheckPrivate on a public bucket = %v", err)
	}
	if err := root.SetBucketPolicy(ctx, "nafir-music", ""); err != nil {
		t.Fatal(err)
	}
	if err := objects.CheckPrivate(ctx); err != nil {
		t.Fatalf("CheckPrivate after removing the policy = %v", err)
	}
}
