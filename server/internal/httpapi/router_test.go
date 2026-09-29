package httpapi

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHealth(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/api/v1/health", nil)
	response := httptest.NewRecorder()

	NewHandler(Config{}).ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, response.Code)
	}
	if body := strings.TrimSpace(response.Body.String()); body != `{"status":"ok"}` {
		t.Fatalf("unexpected response body: %s", body)
	}
}

func TestCORSForConfiguredWebOrigin(t *testing.T) {
	request := httptest.NewRequest(http.MethodOptions, "/api/v1/health", nil)
	request.Header.Set("Origin", "https://music.example.com")
	request.Header.Set("Access-Control-Request-Method", http.MethodGet)
	response := httptest.NewRecorder()

	NewHandler(Config{AllowedOrigin: "https://music.example.com"}).ServeHTTP(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("expected status %d, got %d", http.StatusNoContent, response.Code)
	}
	if origin := response.Header().Get("Access-Control-Allow-Origin"); origin != "https://music.example.com" {
		t.Fatalf("unexpected allowed origin: %q", origin)
	}
}

func TestPreflightFromUnknownOriginIsNotAnswered(t *testing.T) {
	request := httptest.NewRequest(http.MethodOptions, "/api/v1/health", nil)
	request.Header.Set("Origin", "https://evil.example.com")
	request.Header.Set("Access-Control-Request-Method", http.MethodGet)
	response := httptest.NewRecorder()

	NewHandler(Config{AllowedOrigin: "https://music.example.com"}).ServeHTTP(response, request)

	if response.Code == http.StatusNoContent {
		t.Fatalf("preflight from an unknown origin must not succeed")
	}
	if origin := response.Header().Get("Access-Control-Allow-Origin"); origin != "" {
		t.Fatalf("unexpected allowed origin: %q", origin)
	}
}

func TestOptionsOnUnknownPathIsNotFound(t *testing.T) {
	request := httptest.NewRequest(http.MethodOptions, "/api/v1/missing", nil)
	response := httptest.NewRecorder()

	NewHandler(Config{AllowedOrigin: "https://music.example.com"}).ServeHTTP(response, request)

	if response.Code != http.StatusNotFound {
		t.Fatalf("expected status %d, got %d", http.StatusNotFound, response.Code)
	}
}

func TestBotWebhooksAreMountedPerProvider(t *testing.T) {
	var secret string
	handler := NewHandler(Config{Webhooks: map[string]http.Handler{
		"bale": http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			secret = r.PathValue("secret")
			w.WriteHeader(http.StatusOK)
		}),
	}})

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/api/v1/bots/bale/webhook/abc", nil))
	if response.Code != http.StatusOK || secret != "abc" {
		t.Fatalf("bale webhook = %d, secret %q", response.Code, secret)
	}

	response = httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/api/v1/bots/telegram/webhook/abc", nil))
	if response.Code != http.StatusNotFound {
		t.Fatalf("unconfigured provider = %d", response.Code)
	}
}
