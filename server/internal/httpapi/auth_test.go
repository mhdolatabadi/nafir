package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

type memoryUsers struct {
	mu     sync.Mutex
	nextID int
	users  map[string]store.User
	hashes map[string]string
}

func newMemoryUsers() *memoryUsers {
	return &memoryUsers{users: map[string]store.User{}, hashes: map[string]string{}}
}

func (m *memoryUsers) Create(_ context.Context, email, hash string) (store.User, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, user := range m.users {
		if user.Email == email {
			return store.User{}, store.ErrEmailTaken
		}
	}
	m.nextID++
	user := store.User{ID: fmt.Sprintf("user-%d", m.nextID), Email: email, CreatedAt: time.Now()}
	m.users[user.ID] = user
	m.hashes[user.ID] = hash
	return user, nil
}

func (m *memoryUsers) ByEmail(_ context.Context, email string) (store.User, string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for id, user := range m.users {
		if user.Email == email {
			return user, m.hashes[id], nil
		}
	}
	return store.User{}, "", store.ErrNotFound
}

func (m *memoryUsers) ByID(_ context.Context, id string) (store.User, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	user, ok := m.users[id]
	if !ok {
		return store.User{}, store.ErrNotFound
	}
	return user, nil
}

type testAPI struct {
	handler http.Handler
	users   *memoryUsers
	tokens  *auth.Tokens
}

func newTestAPI(t *testing.T) testAPI {
	t.Helper()
	users := newMemoryUsers()
	tokens, err := auth.NewTokens([]byte(strings.Repeat("k", auth.MinSecretBytes)), time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	handlers, err := NewAuthHandlers(users, auth.Passwords{Cost: bcrypt.MinCost}, tokens)
	if err != nil {
		t.Fatal(err)
	}
	return testAPI{handler: NewHandler(Config{Auth: handlers}), users: users, tokens: tokens}
}

func (a testAPI) do(t *testing.T, method, path, body, token string) *httptest.ResponseRecorder {
	t.Helper()
	request := httptest.NewRequest(method, path, bytes.NewBufferString(body))
	request.Header.Set("Content-Type", "application/json")
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}
	response := httptest.NewRecorder()
	a.handler.ServeHTTP(response, request)
	return response
}

func decode[T any](t *testing.T, response *httptest.ResponseRecorder) T {
	t.Helper()
	var value T
	if err := json.Unmarshal(response.Body.Bytes(), &value); err != nil {
		t.Fatalf("decode %q: %v", response.Body.String(), err)
	}
	return value
}

func expectError(t *testing.T, response *httptest.ResponseRecorder, status int, code string) {
	t.Helper()
	if response.Code != status {
		t.Fatalf("expected status %d, got %d: %s", status, response.Code, response.Body.String())
	}
	if got := decode[errorResponse](t, response).Error; got != code {
		t.Fatalf("expected error %q, got %q", code, got)
	}
}

func TestRegisterLoginAndMe(t *testing.T) {
	api := newTestAPI(t)

	registered := api.do(t, http.MethodPost, "/api/v1/auth/register",
		`{"email":"  Listener@Example.com ","password":"correct horse"}`, "")
	if registered.Code != http.StatusCreated {
		t.Fatalf("register: expected 201, got %d: %s", registered.Code, registered.Body.String())
	}
	session := decode[sessionResponse](t, registered)
	if session.User.Email != "listener@example.com" || session.Token == "" {
		t.Fatalf("unexpected session: %+v", session)
	}
	if !session.ExpiresAt.After(time.Now()) {
		t.Fatalf("session already expired: %v", session.ExpiresAt)
	}
	if hash := api.users.hashes[session.User.ID]; hash == "" || strings.Contains(hash, "correct horse") {
		t.Fatalf("password was not hashed: %q", hash)
	}

	loggedIn := api.do(t, http.MethodPost, "/api/v1/auth/login",
		`{"email":"listener@example.com","password":"correct horse"}`, "")
	if loggedIn.Code != http.StatusOK {
		t.Fatalf("login: expected 200, got %d: %s", loggedIn.Code, loggedIn.Body.String())
	}
	token := decode[sessionResponse](t, loggedIn).Token

	me := api.do(t, http.MethodGet, "/api/v1/me", "", token)
	if me.Code != http.StatusOK {
		t.Fatalf("me: expected 200, got %d: %s", me.Code, me.Body.String())
	}
	if user := decode[userResponse](t, me); user.ID != session.User.ID {
		t.Fatalf("me returned %+v, expected %s", user, session.User.ID)
	}
}

func TestRegisterValidation(t *testing.T) {
	api := newTestAPI(t)
	cases := []struct {
		name, body, code string
	}{
		{"malformed json", `{"email":`, "invalid_json"},
		{"unknown field", `{"email":"a@example.com","password":"long enough","admin":true}`, "invalid_json"},
		{"missing email", `{"password":"long enough"}`, "invalid_email"},
		{"display name", `{"email":"Me <a@example.com>","password":"long enough"}`, "invalid_email"},
		{"no domain dot", `{"email":"a@localhost","password":"long enough"}`, "invalid_email"},
		{"short password", `{"email":"a@example.com","password":"short"}`, "invalid_password"},
		{"password over bcrypt limit", `{"email":"a@example.com","password":"` + strings.Repeat("p", 73) + `"}`, "invalid_password"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			expectError(t, api.do(t, http.MethodPost, "/api/v1/auth/register", tc.body, ""), http.StatusBadRequest, tc.code)
		})
	}
}

func TestRegisterDuplicateEmail(t *testing.T) {
	api := newTestAPI(t)
	body := `{"email":"a@example.com","password":"long enough"}`
	api.do(t, http.MethodPost, "/api/v1/auth/register", body, "")
	duplicate := api.do(t, http.MethodPost, "/api/v1/auth/register",
		`{"email":"A@EXAMPLE.COM","password":"another one"}`, "")
	expectError(t, duplicate, http.StatusConflict, "email_taken")
}

func TestLoginRejectsBadCredentials(t *testing.T) {
	api := newTestAPI(t)
	api.do(t, http.MethodPost, "/api/v1/auth/register", `{"email":"a@example.com","password":"long enough"}`, "")

	for name, body := range map[string]string{
		"wrong password": `{"email":"a@example.com","password":"not the one"}`,
		"unknown email":  `{"email":"b@example.com","password":"long enough"}`,
		"invalid email":  `{"email":"nope","password":"long enough"}`,
	} {
		t.Run(name, func(t *testing.T) {
			expectError(t, api.do(t, http.MethodPost, "/api/v1/auth/login", body, ""), http.StatusUnauthorized, "invalid_credentials")
		})
	}
}

func TestMeRejectsMissingOrInvalidTokens(t *testing.T) {
	api := newTestAPI(t)
	orphanToken, _, _ := api.tokens.Issue("deleted-user")

	for name, token := range map[string]string{
		"missing":      "",
		"garbage":      "not-a-token",
		"unknown user": orphanToken,
	} {
		t.Run(name, func(t *testing.T) {
			expectError(t, api.do(t, http.MethodGet, "/api/v1/me", "", token), http.StatusUnauthorized, "unauthorized")
		})
	}
}
