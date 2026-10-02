package storage

import (
	"context"
	"encoding/xml"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeBucket is just enough of the S3 API for listing and batch deletes.
type fakeBucket struct {
	mu      sync.Mutex
	objects map[string]bool
	// failDelete makes every batch delete report an error for each key.
	failDelete bool
}

func (b *fakeBucket) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	b.mu.Lock()
	defer b.mu.Unlock()
	query := r.URL.Query()
	switch {
	case r.Method == http.MethodGet && query.Get("list-type") == "2":
		prefix := query.Get("prefix")
		keys := []string{}
		for key := range b.objects {
			if strings.HasPrefix(key, prefix) {
				keys = append(keys, key)
			}
		}
		sort.Strings(keys)
		var body strings.Builder
		fmt.Fprintf(&body, `<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Name>nafir-music</Name><Prefix>%s</Prefix><KeyCount>%d</KeyCount><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated>`, prefix, len(keys))
		for _, key := range keys {
			fmt.Fprintf(&body, `<Contents><Key>%s</Key><Size>1</Size><LastModified>2026-01-01T00:00:00.000Z</LastModified><ETag>"x"</ETag></Contents>`, key)
		}
		body.WriteString(`</ListBucketResult>`)
		w.Header().Set("Content-Type", "application/xml")
		_, _ = w.Write([]byte(body.String()))
	case r.Method == http.MethodPost && query.Has("delete"):
		var request struct {
			Objects []struct {
				Key string `xml:"Key"`
			} `xml:"Object"`
		}
		if err := xml.NewDecoder(r.Body).Decode(&request); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		var body strings.Builder
		body.WriteString(`<DeleteResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">`)
		for _, object := range request.Objects {
			if b.failDelete {
				fmt.Fprintf(&body, `<Error><Key>%s</Key><Code>AccessDenied</Code><Message>denied</Message></Error>`, object.Key)
				continue
			}
			delete(b.objects, object.Key)
			fmt.Fprintf(&body, `<Deleted><Key>%s</Key></Deleted>`, object.Key)
		}
		body.WriteString(`</DeleteResult>`)
		w.Header().Set("Content-Type", "application/xml")
		_, _ = w.Write([]byte(body.String()))
	default:
		http.Error(w, "unexpected "+r.Method+" "+r.URL.String(), http.StatusNotImplemented)
	}
}

func newFakeStorage(t *testing.T, bucket *fakeBucket) *Storage {
	t.Helper()
	server := httptest.NewServer(bucket)
	t.Cleanup(server.Close)
	endpoint, _ := url.Parse(server.URL)
	s, err := New(Config{
		Endpoint: endpoint.Host, PublicURL: server.URL,
		AccessKey: "access", SecretKey: "secret-secret", Bucket: "nafir-music", URLTTL: time.Minute,
	})
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestRemovePrefixDeletesOnlyThatFolder(t *testing.T) {
	bucket := &fakeBucket{objects: map[string]bool{
		"users/u1/tracks/t1/a.mp3":  true,
		"users/u1/tracks/t2/b.mp3":  true,
		"users/u10/tracks/t3/c.mp3": true,
		"users/u2/tracks/t4/d.mp3":  true,
	}}
	s := newFakeStorage(t, bucket)

	removed, err := s.RemovePrefix(context.Background(), "users/u1/")
	if err != nil || removed != 2 {
		t.Fatalf("RemovePrefix = %d, %v", removed, err)
	}
	if len(bucket.objects) != 2 || !bucket.objects["users/u10/tracks/t3/c.mp3"] || !bucket.objects["users/u2/tracks/t4/d.mp3"] {
		t.Fatalf("left %v", bucket.objects)
	}
	// Nothing left to remove is not an error.
	if removed, err := s.RemovePrefix(context.Background(), "users/u1/"); err != nil || removed != 0 {
		t.Fatalf("second RemovePrefix = %d, %v", removed, err)
	}
}

func TestRemovePrefixReportsFailedDeletes(t *testing.T) {
	bucket := &fakeBucket{objects: map[string]bool{"users/u1/tracks/t1/a.mp3": true}, failDelete: true}
	s := newFakeStorage(t, bucket)
	if _, err := s.RemovePrefix(context.Background(), "users/u1/"); err == nil {
		t.Fatal("a failed delete was reported as success")
	}
	if !bucket.objects["users/u1/tracks/t1/a.mp3"] {
		t.Fatal("object vanished")
	}
}

func TestRemovePrefixRefusesBroadPrefixes(t *testing.T) {
	s := newTestStorage(t, time.Minute)
	for _, prefix := range []string{"", "/", "users", "users//", "/users/u1/", "users/../", "users/u1"} {
		if _, err := s.RemovePrefix(context.Background(), prefix); err == nil {
			t.Errorf("RemovePrefix(%q) was allowed", prefix)
		}
	}
}
