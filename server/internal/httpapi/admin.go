package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/store"
)

type AdminStore interface {
	ListAccounts(context.Context, string, int, int) ([]store.User, bool, error)
	SetVerification(context.Context, string, string, bool) (store.User, error)
}

type AdminHandlers struct {
	auth  *AuthHandlers
	users AdminStore
}

func NewAdminHandlers(auth *AuthHandlers, users AdminStore) *AdminHandlers {
	return &AdminHandlers{auth: auth, users: users}
}

func (h *AdminHandlers) register(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/admin/accounts", h.list)
	mux.HandleFunc("PATCH /api/v1/admin/accounts/{id}/verification", h.verify)
}

// Authorize against a fresh database lookup on every request, not token claims.
func (h *AdminHandlers) authorize(w http.ResponseWriter, r *http.Request) (string, bool) {
	w.Header().Set("Cache-Control", "no-store")
	id, ok := authenticate(h.auth.tokens, w, r)
	if !ok {
		return "", false
	}
	user, err := h.auth.users.ByID(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return "", false
	}
	if err != nil {
		internalError(w, "authorize admin", err)
		return "", false
	}
	if !h.auth.isAdmin(user) {
		writeError(w, http.StatusForbidden, "admin_required")
		return "", false
	}
	return id, true
}

type adminAccountResponse struct {
	userResponse
	CreatedAt  time.Time  `json:"createdAt"`
	VerifiedAt *time.Time `json:"verifiedAt,omitempty"`
}

func (h *AdminHandlers) account(user store.User) adminAccountResponse {
	return adminAccountResponse{
		userResponse: h.auth.userResponse(user),
		CreatedAt:    user.CreatedAt, VerifiedAt: user.VerifiedAt,
	}
}

func (h *AdminHandlers) list(w http.ResponseWriter, r *http.Request) {
	if _, ok := h.authorize(w, r); !ok {
		return
	}
	query := strings.TrimSpace(r.URL.Query().Get("q"))
	offset := 0
	if raw := r.URL.Query().Get("offset"); raw != "" {
		value, err := strconv.Atoi(raw)
		if err != nil || value < 0 || value > 100000 {
			writeError(w, http.StatusBadRequest, "invalid_offset")
			return
		}
		offset = value
	}
	if len(query) > 254 {
		writeError(w, http.StatusBadRequest, "invalid_query")
		return
	}
	users, more, err := h.users.ListAccounts(r.Context(), query, offset, 50)
	if err != nil {
		internalError(w, "list admin accounts", err)
		return
	}
	accounts := make([]adminAccountResponse, 0, len(users))
	for _, user := range users {
		accounts = append(accounts, h.account(user))
	}
	writeJSON(w, http.StatusOK, struct {
		Accounts []adminAccountResponse `json:"accounts"`
		HasMore  bool                   `json:"hasMore"`
	}{accounts, more})
}

func (h *AdminHandlers) verify(w http.ResponseWriter, r *http.Request) {
	actor, ok := h.authorize(w, r)
	if !ok {
		return
	}
	var input struct {
		Verified *bool `json:"verified"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxAuthBodyBytes))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil || input.Verified == nil {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return
	}
	user, err := h.users.SetVerification(r.Context(), r.PathValue("id"), actor, *input.Verified)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "account_not_found")
		return
	}
	if err != nil {
		internalError(w, "set account verification", err)
		return
	}
	writeJSON(w, http.StatusOK, h.account(user))
}
