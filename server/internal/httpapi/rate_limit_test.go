package httpapi

import (
	"net/http/httptest"
	"testing"
	"time"
)

func TestRateLimiterAllowsThenResets(t *testing.T) {
	now := time.Unix(100, 0)
	limiter := NewRateLimiter(RateLimit{Requests: 2, Window: time.Minute}, 10)
	limiter.now = func() time.Time { return now }

	if ok, _ := limiter.Allow("a"); !ok {
		t.Fatal("first request rejected")
	}
	if ok, _ := limiter.Allow("a"); !ok {
		t.Fatal("second request rejected")
	}
	if ok, retry := limiter.Allow("a"); ok || retry != time.Minute {
		t.Fatalf("third request = %v, %v", ok, retry)
	}
	if ok, _ := limiter.Allow("b"); !ok {
		t.Fatal("one key affected another")
	}
	now = now.Add(time.Minute)
	if ok, _ := limiter.Allow("a"); !ok {
		t.Fatal("window did not reset")
	}
}

func TestClientIPUsesOnlyNafirProxyHeader(t *testing.T) {
	request := httptest.NewRequest("GET", "/", nil)
	request.RemoteAddr = "192.0.2.10:1234"
	request.Header.Set("X-Forwarded-For", "203.0.113.99")
	if got := clientIP(request); got != "192.0.2.10" {
		t.Fatalf("trusted spoofable forwarding header: %q", got)
	}
	request.Header.Set(clientIPHeader, "203.0.113.20")
	if got := clientIP(request); got != "203.0.113.20" {
		t.Fatalf("proxy client IP = %q", got)
	}
}
