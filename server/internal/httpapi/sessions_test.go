package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

// newSessionsAPI wires the auth endpoints, account deletion and one plain
// authenticated endpoint (GET /api/v1/bots) to Postgres with revocation on,
// the way cmd/api does.
func newSessionsAPI(t *testing.T) (testAPI, *store.Users) {
	t.Helper()
	users := store.NewUsers(collabTestPool(t))
	sessions := auth.NewSessions(func(ctx context.Context, id string) (int64, error) {
		epoch, err := users.SessionEpoch(ctx, id)
		if errors.Is(err, store.ErrNotFound) {
			return 0, auth.ErrNoAccount
		}
		return epoch, err
	}, time.Minute, 100)
	tokens, err := auth.NewTokens([]byte(strings.Repeat("k", auth.MinSecretBytes)), time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	tokens.WithSessions(sessions)
	handlers, err := NewAuthHandlers(users, auth.Passwords{Cost: bcrypt.MinCost}, tokens, AuthRateLimiters{})
	if err != nil {
		t.Fatal(err)
	}
	handlers.WithAccountDeletion(AccountDeletion{Accounts: users, Objects: &memoryObjects{keys: map[string]bool{}}, Grace: time.Hour}).
		WithSessionRevocation(users, sessions)
	handler := NewHandler(Config{Auth: handlers, Bots: NewBotHandlers(nil, nil, tokens, nil, nil, nil)})
	return testAPI{handler: handler, tokens: tokens}, users
}

func TestRevokingSessionsSignsOutEveryOtherDevice(t *testing.T) {
	api, _ := newSessionsAPI(t)
	phone := registerUser(t, api, "listener@example.com")
	laptop := decode[sessionResponse](t, api.do(t, http.MethodPost, "/api/v1/auth/login",
		`{"email":"listener@example.com","password":"correct horse"}`, ""))
	other := registerUser(t, api, "other@example.com")
	for _, token := range []string{phone.Token, laptop.Token} {
		if response := api.do(t, http.MethodGet, "/api/v1/bots", "", token); response.Code != http.StatusOK {
			t.Fatalf("before revoking: %d", response.Code)
		}
	}

	expectError(t, api.do(t, http.MethodPost, "/api/v1/auth/sessions/revoke", "", ""), http.StatusUnauthorized, "unauthorized")
	response := api.do(t, http.MethodPost, "/api/v1/auth/sessions/revoke", "", phone.Token)
	if response.Code != http.StatusOK || response.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("revoke: %d %s", response.Code, response.Body.String())
	}
	fresh := decode[sessionResponse](t, response)
	if fresh.Token == "" || fresh.User.ID != phone.User.ID {
		t.Fatalf("revoke answered %+v", fresh)
	}

	// Both earlier sessions are over, on every endpoint.
	for _, token := range []string{phone.Token, laptop.Token} {
		expectError(t, api.do(t, http.MethodGet, "/api/v1/bots", "", token), http.StatusUnauthorized, "unauthorized")
		expectError(t, api.do(t, http.MethodGet, "/api/v1/me", "", token), http.StatusUnauthorized, "unauthorized")
		expectError(t, api.do(t, http.MethodPost, "/api/v1/auth/sessions/revoke", "", token), http.StatusUnauthorized, "unauthorized")
	}
	// The device that asked carries on with its new session, and signing in
	// again works.
	if response := api.do(t, http.MethodGet, "/api/v1/bots", "", fresh.Token); response.Code != http.StatusOK {
		t.Fatalf("fresh session: %d", response.Code)
	}
	again := decode[sessionResponse](t, api.do(t, http.MethodPost, "/api/v1/auth/login",
		`{"email":"listener@example.com","password":"correct horse"}`, ""))
	if response := api.do(t, http.MethodGet, "/api/v1/bots", "", again.Token); response.Code != http.StatusOK {
		t.Fatalf("new login: %d", response.Code)
	}
	// Another account is untouched.
	if response := api.do(t, http.MethodGet, "/api/v1/bots", "", other.Token); response.Code != http.StatusOK {
		t.Fatalf("other account: %d", response.Code)
	}
}

func TestDeletedAccountTokensStopEverywhere(t *testing.T) {
	api, _ := newSessionsAPI(t)
	gone := registerUser(t, api, "gone@example.com")
	second := decode[sessionResponse](t, api.do(t, http.MethodPost, "/api/v1/auth/login",
		`{"email":"gone@example.com","password":"correct horse"}`, ""))
	if response := api.do(t, http.MethodGet, "/api/v1/bots", "", second.Token); response.Code != http.StatusOK {
		t.Fatalf("before deleting: %d", response.Code)
	}
	if response := api.do(t, http.MethodDelete, "/api/v1/me", `{"password":"correct horse"}`, gone.Token); response.Code != http.StatusNoContent {
		t.Fatalf("delete: %d %s", response.Code, response.Body.String())
	}
	for _, token := range []string{gone.Token, second.Token} {
		expectError(t, api.do(t, http.MethodGet, "/api/v1/bots", "", token), http.StatusUnauthorized, "unauthorized")
	}
}

// A failed revocation check must not look like a signed-out session: the
// app clears its token on 401.
func TestSessionCheckFailureIsUnavailableNotUnauthorized(t *testing.T) {
	tokens, err := auth.NewTokens([]byte(strings.Repeat("k", auth.MinSecretBytes)), time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	tokens.WithSessions(auth.NewSessions(func(context.Context, string) (int64, error) {
		return 0, errors.New("database down")
	}, time.Minute, 10))
	token, _, _ := tokens.Issue("u1")
	api := testAPI{handler: NewHandler(Config{Bots: NewBotHandlers(nil, nil, tokens, nil, nil, nil)})}
	expectError(t, api.do(t, http.MethodGet, "/api/v1/bots", "", token), http.StatusServiceUnavailable, "unavailable")
	expectError(t, api.do(t, http.MethodGet, "/api/v1/bots", "", "forged"), http.StatusUnauthorized, "unauthorized")
}

func TestRevokeRouteNeedsConfiguration(t *testing.T) {
	api := newTestAPI(t)
	session := registerUser(t, api, "listener@example.com")
	if response := api.do(t, http.MethodPost, "/api/v1/auth/sessions/revoke", "", session.Token); response.Code != http.StatusNotFound && response.Code != http.StatusMethodNotAllowed {
		t.Fatalf("unconfigured revoke route answered %d", response.Code)
	}
}
