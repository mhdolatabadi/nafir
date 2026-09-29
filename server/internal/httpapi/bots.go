package httpapi

import (
	"context"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
)

// BotLinker issues the one-time codes that link a messenger chat to the
// signed-in account.
type BotLinker interface {
	NewCode(ctx context.Context, userID string) (string, time.Time, error)
}

// Bot is a messenger bot people can link. LinkURL, if set, formats a link
// that opens the bot with a code, for example "https://ble.ir/NafirBot?start=%s".
type Bot struct {
	Provider string
	Name     string
	Username string
	LinkURL  string
}

type BotHandlers struct {
	linker BotLinker
	tokens *auth.Tokens
	bots   []Bot
	rate   *RateLimiter
}

// NewBotHandlers serves the bot endpoints. With no bots configured, the list
// is empty and no codes are issued.
func NewBotHandlers(linker BotLinker, tokens *auth.Tokens, bots []Bot, rate *RateLimiter) *BotHandlers {
	return &BotHandlers{linker: linker, tokens: tokens, bots: bots, rate: rate}
}

func (h *BotHandlers) register(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/bots", h.handleList)
	mux.HandleFunc("POST /api/v1/bots/link-code", h.handleLinkCode)
}

type botResponse struct {
	Provider string `json:"provider"`
	Name     string `json:"name"`
	Username string `json:"username,omitempty"`
	LinkURL  string `json:"linkUrl,omitempty"`
}

type botListResponse struct {
	Bots []botResponse `json:"bots"`
}

type linkCodeResponse struct {
	Code      string        `json:"code"`
	ExpiresAt time.Time     `json:"expiresAt"`
	Bots      []botResponse `json:"bots"`
}

func (h *BotHandlers) responses(code string) []botResponse {
	bots := make([]botResponse, 0, len(h.bots))
	for _, b := range h.bots {
		r := botResponse{Provider: b.Provider, Name: b.Name, Username: b.Username}
		if code != "" && b.LinkURL != "" {
			r.LinkURL = fmtLink(b.LinkURL, code)
		}
		bots = append(bots, r)
	}
	return bots
}

func fmtLink(template, code string) string {
	return strings.Replace(template, "%s", url.QueryEscape(code), 1)
}

func (h *BotHandlers) handleList(w http.ResponseWriter, r *http.Request) {
	if _, ok := authenticate(h.tokens, w, r); !ok {
		return
	}
	writeJSON(w, http.StatusOK, botListResponse{Bots: h.responses("")})
}

func (h *BotHandlers) handleLinkCode(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	if h.linker == nil || len(h.bots) == 0 {
		writeError(w, http.StatusNotFound, "no_bots")
		return
	}
	if !enforceRateLimit(w, h.rate, userID) {
		return
	}
	code, expiresAt, err := h.linker.NewCode(r.Context(), userID)
	if err != nil {
		internalError(w, "create bot link code", err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusCreated, linkCodeResponse{
		Code: code, ExpiresAt: expiresAt.UTC(), Bots: h.responses(code),
	})
}
