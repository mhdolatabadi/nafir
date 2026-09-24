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
