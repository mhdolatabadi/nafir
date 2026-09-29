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
	"github.com/mhdolatabadi/nafir/server/internal/bot"
)

type fakeLinker struct {
	userIDs []string
	linked  []string
}

func (f *fakeLinker) LinkedProviders(_ context.Context, _ string) ([]string, error) {
	return f.linked, nil
}

type fakeSender struct {
	calls []string
	err   error
}

func (f *fakeSender) Send(_ context.Context, provider, userID, trackID string) error {
	f.calls = append(f.calls, provider+"/"+userID+"/"+trackID)
	return f.err
}

func (f *fakeLinker) NewCode(_ context.Context, userID string) (string, time.Time, error) {
	f.userIDs = append(f.userIDs, userID)
	return "12345678", time.Date(2026, 9, 29, 12, 10, 0, 0, time.UTC), nil
}

func botTestServer(t *testing.T, linker BotLinker, bots []Bot) (http.Handler, string) {
	return botTestServerWithSender(t, linker, nil, bots)
}

func botTestServerWithSender(t *testing.T, linker BotLinker, sender BotSender, bots []Bot) (http.Handler, string) {
	t.Helper()
	tokens, err := auth.NewTokens([]byte(strings.Repeat("k", auth.MinSecretBytes)), time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	token, _, _ := tokens.Issue("u1")
	rate := NewRateLimiter(RateLimit{Requests: 2, Window: time.Hour}, 100)
	sendRate := NewRateLimiter(RateLimit{Requests: 3, Window: time.Hour}, 100)
	return NewHandler(Config{Bots: NewBotHandlers(linker, sender, tokens, bots, rate, sendRate)}), token
}

func botRequest(handler http.Handler, method, path, token string, body ...string) *httptest.ResponseRecorder {
	request := httptest.NewRequest(method, path, strings.NewReader(strings.Join(body, "")))
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
	handler, token := botTestServer(t, &fakeLinker{linked: []string{"bale"}}, []Bot{
		{Provider: "bale", Name: "بله", Username: "NafirBot", LinkURL: "https://ble.ir/NafirBot?start=%s"},
	})
	response := botRequest(handler, http.MethodGet, "/api/v1/bots", token)
	var body botListResponse
	json.NewDecoder(response.Body).Decode(&body)
	if response.Code != http.StatusOK || len(body.Bots) != 1 || body.Bots[0].Username != "NafirBot" ||
		body.Bots[0].LinkURL != "" || !body.Bots[0].Linked {
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

func TestSendTrackToBot(t *testing.T) {
	sender := &fakeSender{}
	handler, token := botTestServerWithSender(t, &fakeLinker{}, sender, []Bot{{Provider: "bale", Name: "بله"}})
	send := func(body string) *httptest.ResponseRecorder {
		return botRequest(handler, http.MethodPost, "/api/v1/bots/bale/send", token, body)
	}

	if response := botRequest(handler, http.MethodPost, "/api/v1/bots/bale/send", "", `{"trackId":"t1"}`); response.Code != http.StatusUnauthorized {
		t.Fatalf("without a token = %d", response.Code)
	}
	if response := send(`{"trackId":"t1"}`); response.Code != http.StatusAccepted {
		t.Fatalf("send = %d %s", response.Code, response.Body)
	}
	if len(sender.calls) != 1 || sender.calls[0] != "bale/u1/t1" {
		t.Fatalf("calls = %v", sender.calls)
	}
	if response := send(`{}`); response.Code != http.StatusBadRequest {
		t.Fatalf("missing track = %d", response.Code)
	}

	for err, want := range map[error]int{
		bot.ErrNotLinked:     http.StatusConflict,
		bot.ErrTrackTooLarge: http.StatusRequestEntityTooLarge,
	} {
		sender.err = err
		handler, token := botTestServerWithSender(t, &fakeLinker{}, sender, []Bot{{Provider: "bale", Name: "بله"}})
		if response := botRequest(handler, http.MethodPost, "/api/v1/bots/bale/send", token, `{"trackId":"t1"}`); response.Code != want {
			t.Errorf("%v = %d, want %d", err, response.Code, want)
		}
	}
	sender.err = bot.ErrTrackNotFound
	if response := send(`{"trackId":"t1"}`); response.Code != http.StatusNotFound {
		t.Fatalf("not found = %d", response.Code)
	}
	if response := send(`{"trackId":"t1"}`); response.Code != http.StatusTooManyRequests {
		t.Fatalf("fourth send in the window = %d", response.Code)
	}
}
