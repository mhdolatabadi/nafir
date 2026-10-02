package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

// memoryObjects is a bucket of object keys for prefix removal.
type memoryObjects struct {
	mu      sync.Mutex
	keys    map[string]bool
	fail    bool
	removed []string
}

func (m *memoryObjects) RemovePrefix(_ context.Context, prefix string) (int, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.fail {
		return 0, errors.New("storage down")
	}
	m.removed = append(m.removed, prefix)
	count := 0
	for key := range m.keys {
		if strings.HasPrefix(key, prefix) {
			delete(m.keys, key)
			count++
		}
	}
	return count, nil
}

// memoryAccounts deletes from memoryUsers the way store.Users.Delete does.
type memoryAccounts struct {
	users   *memoryUsers
	deleted []string
}

func (m *memoryAccounts) Delete(_ context.Context, userID string, grace time.Duration) (store.AccountDeletion, error) {
	m.users.mu.Lock()
	defer m.users.mu.Unlock()
	if _, ok := m.users.users[userID]; !ok {
		return store.AccountDeletion{}, store.ErrNotFound
	}
	delete(m.users.users, userID)
	delete(m.users.hashes, userID)
	m.deleted = append(m.deleted, userID)
	now := time.Now()
	return store.AccountDeletion{UserID: userID, ObjectPrefix: store.UserObjectPrefix(userID), DeletedAt: now, PurgeAfter: now.Add(grace)}, nil
}

func newDeletionAPI(t *testing.T, objects *memoryObjects, rate *RateLimiter) (testAPI, *memoryAccounts) {
	t.Helper()
	users := newMemoryUsers()
	tokens, err := auth.NewTokens([]byte(strings.Repeat("k", auth.MinSecretBytes)), time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	handlers, err := NewAuthHandlers(users, auth.Passwords{Cost: bcrypt.MinCost}, tokens, AuthRateLimiters{})
	if err != nil {
		t.Fatal(err)
	}
	accounts := &memoryAccounts{users: users}
	handlers.WithAccountDeletion(AccountDeletion{Accounts: accounts, Objects: objects, Rate: rate, Grace: time.Hour})
	return testAPI{handler: NewHandler(Config{Auth: handlers}), users: users, tokens: tokens}, accounts
}

func registerUser(t *testing.T, api testAPI, email string) sessionResponse {
	t.Helper()
	response := api.do(t, http.MethodPost, "/api/v1/auth/register", `{"email":"`+email+`","password":"correct horse"}`, "")
	if response.Code != http.StatusCreated {
		t.Fatalf("register: %d %s", response.Code, response.Body.String())
	}
	return decode[sessionResponse](t, response)
}

func TestDeleteAccount(t *testing.T) {
	objects := &memoryObjects{keys: map[string]bool{}}
	api, accounts := newDeletionAPI(t, objects, nil)
	gone := registerUser(t, api, "gone@example.com")
	kept := registerUser(t, api, "kept@example.com")
	objects.keys["users/"+gone.User.ID+"/tracks/t1/a.mp3"] = true
	objects.keys["users/"+kept.User.ID+"/tracks/t2/b.mp3"] = true

	expectError(t, api.do(t, http.MethodDelete, "/api/v1/me", `{"password":"correct horse"}`, ""), http.StatusUnauthorized, "unauthorized")
	expectError(t, api.do(t, http.MethodDelete, "/api/v1/me", `{"password":"correct horse"}`, "forged"), http.StatusUnauthorized, "unauthorized")
	expectError(t, api.do(t, http.MethodDelete, "/api/v1/me", `{"password":"wrong horse!"}`, gone.Token), http.StatusForbidden, "invalid_password")
	expectError(t, api.do(t, http.MethodDelete, "/api/v1/me", `{}`, gone.Token), http.StatusForbidden, "invalid_password")
	expectError(t, api.do(t, http.MethodDelete, "/api/v1/me", `{"password":"`+strings.Repeat("x", auth.MaxPasswordBytes+1)+`"}`, gone.Token), http.StatusForbidden, "invalid_password")
	expectError(t, api.do(t, http.MethodDelete, "/api/v1/me", `not json`, gone.Token), http.StatusBadRequest, "invalid_json")
	expectError(t, api.do(t, http.MethodDelete, "/api/v1/me", `{"password":"correct horse","email":"x"}`, gone.Token), http.StatusBadRequest, "invalid_json")
	if len(accounts.deleted) != 0 || len(objects.removed) != 0 {
		t.Fatalf("deleted %v, removed %v before a correct password", accounts.deleted, objects.removed)
	}

	response := api.do(t, http.MethodDelete, "/api/v1/me", `{"password":"correct horse"}`, gone.Token)
	if response.Code != http.StatusNoContent {
		t.Fatalf("delete: %d %s", response.Code, response.Body.String())
	}
	if len(accounts.deleted) != 1 || accounts.deleted[0] != gone.User.ID {
		t.Fatalf("deleted = %v", accounts.deleted)
	}
	if len(objects.keys) != 1 || !objects.keys["users/"+kept.User.ID+"/tracks/t2/b.mp3"] {
		t.Fatalf("objects left = %v", objects.keys)
	}

	// The old session and password stop working; the other account doesn't.
	expectError(t, api.do(t, http.MethodGet, "/api/v1/me", "", gone.Token), http.StatusUnauthorized, "unauthorized")
	expectError(t, api.do(t, http.MethodDelete, "/api/v1/me", `{"password":"correct horse"}`, gone.Token), http.StatusUnauthorized, "unauthorized")
	expectError(t, api.do(t, http.MethodPost, "/api/v1/auth/login", `{"email":"gone@example.com","password":"correct horse"}`, ""), http.StatusUnauthorized, "invalid_credentials")
	if response := api.do(t, http.MethodGet, "/api/v1/me", "", kept.Token); response.Code != http.StatusOK {
		t.Fatalf("other account: %d", response.Code)
	}
}

// When storage fails the account is still deleted; the purge job removes
// the objects later.
func TestDeleteAccountWhenStorageFails(t *testing.T) {
	objects := &memoryObjects{keys: map[string]bool{}, fail: true}
	api, accounts := newDeletionAPI(t, objects, nil)
	session := registerUser(t, api, "gone@example.com")
	response := api.do(t, http.MethodDelete, "/api/v1/me", `{"password":"correct horse"}`, session.Token)
	if response.Code != http.StatusNoContent || len(accounts.deleted) != 1 {
		t.Fatalf("delete: %d %s, deleted %v", response.Code, response.Body.String(), accounts.deleted)
	}
}

func TestDeleteAccountIsRateLimited(t *testing.T) {
	limiter := NewRateLimiter(RateLimit{Requests: 2, Window: time.Hour}, 100)
	api, accounts := newDeletionAPI(t, &memoryObjects{keys: map[string]bool{}}, limiter)
	session := registerUser(t, api, "gone@example.com")
	for range 2 {
		expectError(t, api.do(t, http.MethodDelete, "/api/v1/me", `{"password":"wrong horse!"}`, session.Token), http.StatusForbidden, "invalid_password")
	}
	response := api.do(t, http.MethodDelete, "/api/v1/me", `{"password":"correct horse"}`, session.Token)
	expectError(t, response, http.StatusTooManyRequests, "rate_limited")
	if response.Header().Get("Retry-After") == "" || len(accounts.deleted) != 0 {
		t.Fatalf("retry-after %q, deleted %v", response.Header().Get("Retry-After"), accounts.deleted)
	}
}

func TestDeleteAccountRouteNeedsConfiguration(t *testing.T) {
	api := newTestAPI(t)
	session := registerUser(t, api, "a@example.com")
	if response := api.do(t, http.MethodDelete, "/api/v1/me", `{"password":"correct horse"}`, session.Token); response.Code != http.StatusMethodNotAllowed {
		t.Fatalf("unconfigured delete: %d", response.Code)
	}
}

// Against Postgres: the account and its data go, and its storage prefix is
// removed and queued for the purge job.
func TestDeleteAccountWithPostgres(t *testing.T) {
	pool := collabTestPool(t)
	ctx := context.Background()
	users := store.NewUsers(pool)
	tracks := store.NewTracks(pool)
	playlists := store.NewPlaylists(pool)
	tokens, _ := auth.NewTokens([]byte(strings.Repeat("k", auth.MinSecretBytes)), time.Hour)
	passwords := auth.Passwords{Cost: bcrypt.MinCost}
	handlers, err := NewAuthHandlers(users, passwords, tokens, AuthRateLimiters{})
	if err != nil {
		t.Fatal(err)
	}
	objects := &memoryObjects{keys: map[string]bool{}}
	handlers.WithAccountDeletion(AccountDeletion{Accounts: users, Objects: objects, Grace: time.Hour})
	api := testAPI{handler: NewHandler(Config{Auth: handlers}), tokens: tokens}

	hash, _ := passwords.Hash("correct horse")
	gone, _ := users.Create(ctx, "gone@example.com", hash)
	kept, _ := users.Create(ctx, "kept@example.com", hash)
	goneTrack, err := tracks.Create(ctx, gone.ID, store.NewTrack{Title: "g", FileName: "g.mp3", ContentType: "audio/mpeg", SizeBytes: 1})
	if err != nil {
		t.Fatal(err)
	}
	keptTrack, _ := tracks.Create(ctx, kept.ID, store.NewTrack{Title: "k", FileName: "k.mp3", ContentType: "audio/mpeg", SizeBytes: 1})
	objects.keys[goneTrack.StorageKey] = true
	objects.keys[keptTrack.StorageKey] = true
	list, _ := playlists.Create(ctx, gone.ID, "mine")
	goneToken, _, _ := tokens.Issue(gone.ID)
	keptToken, _, _ := tokens.Issue(kept.ID)

	// Someone else's session can only ever delete their own account.
	expectError(t, api.do(t, http.MethodDelete, "/api/v1/me", `{"password":"wrong horse!"}`, keptToken), http.StatusForbidden, "invalid_password")
	expectError(t, api.do(t, http.MethodDelete, "/api/v1/me", `{"password":"wrong horse!"}`, goneToken), http.StatusForbidden, "invalid_password")
	if _, err := users.ByID(ctx, gone.ID); err != nil {
		t.Fatalf("wrong password deleted the account: %v", err)
	}

	if response := api.do(t, http.MethodDelete, "/api/v1/me", `{"password":"correct horse"}`, goneToken); response.Code != http.StatusNoContent {
		t.Fatalf("delete: %d %s", response.Code, response.Body.String())
	}
	if _, err := users.ByID(ctx, gone.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("account still there: %v", err)
	}
	if _, err := tracks.ForOwner(ctx, gone.ID, goneTrack.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("track still there: %v", err)
	}
	if _, err := playlists.ForUser(ctx, gone.ID, list.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("playlist still there: %v", err)
	}
	if objects.keys[goneTrack.StorageKey] || !objects.keys[keptTrack.StorageKey] {
		t.Fatalf("objects = %v", objects.keys)
	}
	if _, err := tracks.ForOwner(ctx, kept.ID, keptTrack.ID); err != nil {
		t.Fatalf("other user's track: %v", err)
	}
	pending, err := users.PendingAccountPurges(ctx, 10)
	if err != nil || len(pending) != 1 || pending[0].UserID != gone.ID || pending[0].ObjectPrefix != "users/"+gone.ID+"/" {
		t.Fatalf("purge queue = %+v, %v", pending, err)
	}
	expectError(t, api.do(t, http.MethodGet, "/api/v1/me", "", goneToken), http.StatusUnauthorized, "unauthorized")
}
