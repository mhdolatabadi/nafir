package httpapi

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestRegisterRejectsCommonAndPersonalPasswords(t *testing.T) {
	api := newTestAPI(t)
	for _, password := range []string{"password", "12345678", "Qwertyuiop", "aaaaaaaaaa", "listener", "listener@example.com"} {
		response := api.do(t, http.MethodPost, "/api/v1/auth/register",
			`{"email":"listener@example.com","password":"`+password+`"}`, "")
		expectError(t, response, http.StatusBadRequest, "weak_password")
	}
	if len(api.users.users) != 0 {
		t.Fatal("an account was created with a weak password")
	}
	if response := api.do(t, http.MethodPost, "/api/v1/auth/register",
		`{"email":"listener@example.com","password":"correct horse"}`, ""); response.Code != http.StatusCreated {
		t.Fatalf("a strong password was refused: %d %s", response.Code, response.Body.String())
	}
}

// Guesses for one account are limited however many IPs they come from, and
// an unknown email is limited exactly like a real one.
func TestLoginIsLimitedPerAccountAcrossIPs(t *testing.T) {
	api := newTestAPIWithLimiters(t, AuthRateLimiters{
		Login:        NewRateLimiter(RateLimit{Requests: 100, Window: time.Hour}, 100),
		LoginAccount: NewRateLimiter(RateLimit{Requests: 3, Window: time.Hour}, 100),
	})
	api.do(t, http.MethodPost, "/api/v1/auth/register", `{"email":"victim@example.com","password":"correct horse"}`, "")

	login := func(ip, email, password string) *httptest.ResponseRecorder {
		request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login",
			strings.NewReader(`{"email":"`+email+`","password":"`+password+`"}`))
		request.Header.Set(clientIPHeader, ip)
		response := httptest.NewRecorder()
		api.handler.ServeHTTP(response, request)
		return response
	}
	for _, email := range []string{"Victim@Example.com", "nobody@example.com"} {
		for i := range 3 {
			ip := "198.51.100." + string(rune('1'+i))
			expectError(t, login(ip, email, "wrong guess"), http.StatusUnauthorized, "invalid_credentials")
		}
		response := login("203.0.113.9", email, "wrong guess")
		expectError(t, response, http.StatusTooManyRequests, "rate_limited")
		if response.Header().Get("Retry-After") == "" {
			t.Fatal("missing Retry-After")
		}
	}
	// Other accounts are unaffected.
	expectError(t, login("203.0.113.9", "other@example.com", "wrong guess"), http.StatusUnauthorized, "invalid_credentials")
}

func TestOpenWhenFullLimiterLetsNewKeysThrough(t *testing.T) {
	closed := NewRateLimiter(RateLimit{Requests: 1, Window: time.Hour}, 2)
	open := NewRateLimiter(RateLimit{Requests: 1, Window: time.Hour}, 2).OpenWhenFull()
	for _, key := range []string{"a", "b"} {
		closed.Allow(key)
		open.Allow(key)
	}
	if ok, _ := closed.Allow("c"); ok {
		t.Fatal("a full limiter admitted a new key")
	}
	if ok, _ := open.Allow("c"); !ok {
		t.Fatal("an open-when-full limiter refused a new key")
	}
	// Tracked keys stay limited either way.
	if ok, _ := open.Allow("a"); ok {
		t.Fatal("a tracked key went over its limit")
	}
}

func TestClientIPGroupsIPv6ByPrefix(t *testing.T) {
	for header, want := range map[string]string{
		"2001:db8:1:2:aaaa::1":    "2001:db8:1:2::/64",
		"2001:db8:1:2:ffff:1:2:3": "2001:db8:1:2::/64",
		"2001:db8:1:3::1":         "2001:db8:1:3::/64",
		"::ffff:203.0.113.7":      "203.0.113.7",
		"203.0.113.7":             "203.0.113.7",
		"fe80::1%eth0":            "fe80::/64",
	} {
		request := httptest.NewRequest(http.MethodGet, "/", nil)
		request.Header.Set(clientIPHeader, header)
		if got := clientIP(request); got != want {
			t.Errorf("clientIP(%q) = %q, want %q", header, got, want)
		}
	}
	request := httptest.NewRequest(http.MethodGet, "/", nil)
	request.RemoteAddr = "[2001:db8:9:9:1::5]:4321"
	if got := clientIP(request); got != "2001:db8:9:9::/64" {
		t.Errorf("RemoteAddr fallback = %q", got)
	}
}
