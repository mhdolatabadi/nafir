package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/bot"
)

// BotLinker issues the one-time codes that link a messenger chat to the
// signed-in account, and says which bots the account has linked.
type BotLinker interface {
	NewCode(ctx context.Context, userID string) (string, time.Time, error)
	LinkedProviders(ctx context.Context, userID string) ([]string, error)
}

// BotSender has a bot send one of the user's tracks to their linked chats.
type BotSender interface {
	Send(ctx context.Context, provider, userID, trackID string) error
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
	linker   BotLinker
	sender   BotSender
	tokens   *auth.Tokens
	bots     []Bot
	rate     *RateLimiter
	sendRate *RateLimiter
}

// NewBotHandlers serves the bot endpoints. With no bots configured, the list
// is empty and nothing is issued or sent.
func NewBotHandlers(linker BotLinker, sender BotSender, tokens *auth.Tokens, bots []Bot, rate, sendRate *RateLimiter) *BotHandlers {
	return &BotHandlers{linker: linker, sender: sender, tokens: tokens, bots: bots, rate: rate, sendRate: sendRate}
}

func (h *BotHandlers) register(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/bots", h.handleList)
	mux.HandleFunc("POST /api/v1/bots/link-code", h.handleLinkCode)
	mux.HandleFunc("POST /api/v1/bots/{provider}/send", h.handleSend)
}

type botResponse struct {
	Provider string `json:"provider"`
	Name     string `json:"name"`
	Username string `json:"username,omitempty"`
	LinkURL  string `json:"linkUrl,omitempty"`
	// Linked says the account has a chat linked with this bot.
	Linked bool `json:"linked"`
}

type botListResponse struct {
	Bots []botResponse `json:"bots"`
}

type linkCodeResponse struct {
	Code      string        `json:"code"`
	ExpiresAt time.Time     `json:"expiresAt"`
	Bots      []botResponse `json:"bots"`
}

func (h *BotHandlers) responses(code string, linked []string) []botResponse {
	bots := make([]botResponse, 0, len(h.bots))
	for _, b := range h.bots {
		r := botResponse{Provider: b.Provider, Name: b.Name, Username: b.Username, Linked: slices.Contains(linked, b.Provider)}
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
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	var linked []string
	if h.linker != nil && len(h.bots) > 0 {
		var err error
		if linked, err = h.linker.LinkedProviders(r.Context(), userID); err != nil {
			internalError(w, "list linked bots", err)
			return
		}
	}
	writeJSON(w, http.StatusOK, botListResponse{Bots: h.responses("", linked)})
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
		Code: code, ExpiresAt: expiresAt.UTC(), Bots: h.responses(code, nil),
	})
}

type sendRequest struct {
	TrackID string `json:"trackId"`
}

// handleSend queues one of the caller's tracks for the bot to post in their
// linked chats. Delivery happens in the background; the bot reports
// failures in the chat.
func (h *BotHandlers) handleSend(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	if h.sender == nil {
		writeError(w, http.StatusNotFound, "no_bots")
		return
	}
	if !enforceRateLimit(w, h.sendRate, userID) {
		return
	}
	var input sendRequest
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<10))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil || input.TrackID == "" {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return
	}
	err := h.sender.Send(r.Context(), r.PathValue("provider"), userID, input.TrackID)
	switch {
	case errors.Is(err, bot.ErrUnknownProvider), errors.Is(err, bot.ErrTrackNotFound):
		writeError(w, http.StatusNotFound, "not_found")
	case errors.Is(err, bot.ErrNotLinked):
		writeError(w, http.StatusConflict, "not_linked")
	case errors.Is(err, bot.ErrTrackTooLarge):
		writeError(w, http.StatusRequestEntityTooLarge, "too_large")
	case err != nil:
		internalError(w, "send track to bot", err)
	default:
		w.WriteHeader(http.StatusAccepted)
	}
}
