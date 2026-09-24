package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/mail"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

const maxAuthBodyBytes = 4 << 10

// UserStore is the persistence the auth endpoints need; *store.Users implements it.
type UserStore interface {
	Create(ctx context.Context, email, passwordHash string) (store.User, error)
	ByEmail(ctx context.Context, email string) (store.User, string, error)
	ByID(ctx context.Context, id string) (store.User, error)
}

type AuthHandlers struct {
	users     UserStore
	passwords auth.Passwords
	tokens    *auth.Tokens
	// dummyHash is compared against when an email is unknown, so a login for a
	// missing account takes as long as one with a wrong password.
	dummyHash string
}

func NewAuthHandlers(users UserStore, passwords auth.Passwords, tokens *auth.Tokens) (*AuthHandlers, error) {
	dummyHash, err := passwords.Hash("nafir-timing-equaliser")
	if err != nil {
		return nil, err
	}
	return &AuthHandlers{users: users, passwords: passwords, tokens: tokens, dummyHash: dummyHash}, nil
}

func (h *AuthHandlers) register(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/auth/register", h.handleRegister)
	mux.HandleFunc("POST /api/v1/auth/login", h.handleLogin)
	mux.HandleFunc("GET /api/v1/me", h.handleMe)
}

type credentials struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type userResponse struct {
	ID    string `json:"id"`
	Email string `json:"email"`
}

type sessionResponse struct {
	Token     string       `json:"token"`
	ExpiresAt time.Time    `json:"expiresAt"`
	User      userResponse `json:"user"`
}

func (h *AuthHandlers) handleRegister(w http.ResponseWriter, r *http.Request) {
	input, ok := decodeCredentials(w, r)
	if !ok {
		return
	}
	email, ok := normalizeEmail(input.Email)
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid_email")
		return
	}
	if utf8.RuneCountInString(input.Password) < auth.MinPasswordLength || len(input.Password) > auth.MaxPasswordBytes {
		writeError(w, http.StatusBadRequest, "invalid_password")
		return
	}

	hash, err := h.passwords.Hash(input.Password)
	if err != nil {
		internalError(w, "hash password", err)
		return
	}
	user, err := h.users.Create(r.Context(), email, hash)
	if errors.Is(err, store.ErrEmailTaken) {
		writeError(w, http.StatusConflict, "email_taken")
		return
	}
	if err != nil {
		internalError(w, "create user", err)
		return
	}
	h.writeSession(w, http.StatusCreated, user)
}

func (h *AuthHandlers) handleLogin(w http.ResponseWriter, r *http.Request) {
	input, ok := decodeCredentials(w, r)
	if !ok {
		return
	}
	email, validEmail := normalizeEmail(input.Email)
	if !validEmail || len(input.Password) > auth.MaxPasswordBytes {
		writeError(w, http.StatusUnauthorized, "invalid_credentials")
		return
	}

	user, hash, err := h.users.ByEmail(r.Context(), email)
	if errors.Is(err, store.ErrNotFound) {
		_ = h.passwords.Verify(h.dummyHash, input.Password)
		writeError(w, http.StatusUnauthorized, "invalid_credentials")
		return
	}
	if err != nil {
		internalError(w, "find user", err)
		return
	}
	if err := h.passwords.Verify(hash, input.Password); err != nil {
		if !errors.Is(err, auth.ErrPasswordMismatch) {
			internalError(w, "verify password", err)
			return
		}
		writeError(w, http.StatusUnauthorized, "invalid_credentials")
		return
	}
	h.writeSession(w, http.StatusOK, user)
}

func (h *AuthHandlers) handleMe(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	user, err := h.users.ByID(r.Context(), userID)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if err != nil {
		internalError(w, "find user", err)
		return
	}
	writeJSON(w, http.StatusOK, userResponse{ID: user.ID, Email: user.Email})
}

func (h *AuthHandlers) writeSession(w http.ResponseWriter, status int, user store.User) {
	token, expiresAt, err := h.tokens.Issue(user.ID)
	if err != nil {
		internalError(w, "issue token", err)
		return
	}
	writeJSON(w, status, sessionResponse{
		Token:     token,
		ExpiresAt: expiresAt.UTC(),
		User:      userResponse{ID: user.ID, Email: user.Email},
	})
}

func decodeCredentials(w http.ResponseWriter, r *http.Request) (credentials, bool) {
	var input credentials
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxAuthBodyBytes))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return credentials{}, false
	}
	return input, true
}

// normalizeEmail trims and lower-cases an address and rejects anything that is
// not a bare address, such as "Name <a@b.c>".
func normalizeEmail(raw string) (string, bool) {
	email := strings.ToLower(strings.TrimSpace(raw))
	if email == "" || len(email) > 254 {
		return "", false
	}
	address, err := mail.ParseAddress(email)
	if err != nil || address.Address != email || !strings.Contains(email[strings.LastIndex(email, "@"):], ".") {
		return "", false
	}
	return email, true
}

// authenticate returns the user ID from a valid bearer token, or writes 401.
func authenticate(tokens *auth.Tokens, w http.ResponseWriter, r *http.Request) (string, bool) {
	token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if ok && token != "" {
		if userID, err := tokens.Verify(token); err == nil {
			return userID, true
		}
	}
	writeError(w, http.StatusUnauthorized, "unauthorized")
	return "", false
}

// internalError logs the cause without request data, so passwords never reach the logs.
func internalError(w http.ResponseWriter, action string, err error) {
	slog.Error("request failed", "action", action, "error", err)
	writeError(w, http.StatusInternalServerError, "internal_error")
}
