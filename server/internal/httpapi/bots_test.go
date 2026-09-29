package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
)

type fakeLinker struct{ userIDs []string }

func (f *fakeLinker) NewCode(_ context.Context, userID string) (string, time.Time, error) {
	f.userIDs = append(f.userIDs, userID)
	return "12345678", time.Date(2026, 9, 29, 12, 10, 0, 0, time.UTC), nil
}

func botTestServer(t *testing.T, linker BotLinker, bots []Bot) (http.Handler, string) {
	t.Helper()
	tokens, err := auth.NewTokens([]byte(strings.Repeat("k", auth.MinSecretBytes)), time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	token, _, _ := tokens.Issue("u1")
	rate := NewRateLimiter(RateLimit{Requests: 2, Window: time.Hour}, 100)
	return NewHandler(Config{Bots: NewBotHandlers(linker, tokens, bots, rate)}), token
}

func botRequest(handler http.Handler, method, path, token string) *httptest.ResponseRecorder {
	request := httptest.NewRequest(method, path, nil)
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	return response
}

func TestLinkCodeIsIssuedToTheSignedInUser(t *testing.T) {
	linker := &fakeLinker{}
	handler, token := botTestServer(t, linker, []Bot{
		{Provider: "bale", Name: "بله", Username: "NafirBot", LinkURL: "https://ble.ir/NafirBot?start=%s"},
	})

	if response := botRequest(handler, http.MethodPost, "/api/v1/bots/link-code", ""); response.Code != http.StatusUnauthorized {
		t.Fatalf("without a token = %d", response.Code)
	}

	response := botRequest(handler, http.MethodPost, "/api/v1/bots/link-code", token)
	if response.Code != http.StatusCreated || response.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("link code = %d %s", response.Code, response.Body)
	}
	var body linkCodeResponse
	json.NewDecoder(response.Body).Decode(&body)
	if body.Code != "12345678" || len(body.Bots) != 1 || body.Bots[0].LinkURL != "https://ble.ir/NafirBot?start=12345678" {
		t.Fatalf("body = %+v", body)
	}
	if len(linker.userIDs) != 1 || linker.userIDs[0] != "u1" {
		t.Fatalf("code issued for %v", linker.userIDs)
	}

	botRequest(handler, http.MethodPost, "/api/v1/bots/link-code", token)
	if response := botRequest(handler, http.MethodPost, "/api/v1/bots/link-code", token); response.Code != http.StatusTooManyRequests {
		t.Fatalf("third code in the window = %d", response.Code)
	}
}

func TestBotListNeverCarriesACode(t *testing.T) {
	handler, token := botTestServer(t, &fakeLinker{}, []Bot{
		{Provider: "bale", Name: "بله", Username: "NafirBot", LinkURL: "https://ble.ir/NafirBot?start=%s"},
	})
	response := botRequest(handler, http.MethodGet, "/api/v1/bots", token)
	var body botListResponse
	json.NewDecoder(response.Body).Decode(&body)
	if response.Code != http.StatusOK || len(body.Bots) != 1 || body.Bots[0].Username != "NafirBot" || body.Bots[0].LinkURL != "" {
		t.Fatalf("bots = %d %+v", response.Code, body)
	}
}

func TestWithoutBotsTheListIsEmptyAndNoCodesAreIssued(t *testing.T) {
	handler, token := botTestServer(t, nil, nil)
	response := botRequest(handler, http.MethodGet, "/api/v1/bots", token)
	if response.Code != http.StatusOK || strings.TrimSpace(response.Body.String()) != `{"bots":[]}` {
		t.Fatalf("bots = %d %s", response.Code, response.Body)
	}
	if response := botRequest(handler, http.MethodPost, "/api/v1/bots/link-code", token); response.Code != http.StatusNotFound {
		t.Fatalf("link code without bots = %d", response.Code)
	}
}
