package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

const (
	maxPlaylistBodyBytes = 64 << 10
	maxPlaylistNameRunes = 200
	maxPlaylistTracks    = 1000
)

type PlaylistStore interface {
	ListForOwner(ctx context.Context, ownerID string) ([]store.Playlist, error)
	ForOwner(ctx context.Context, ownerID, playlistID string) (store.Playlist, error)
	Create(ctx context.Context, ownerID, name string) (store.Playlist, error)
	Rename(ctx context.Context, ownerID, playlistID, name string) (store.Playlist, error)
	ReplaceTracks(ctx context.Context, ownerID, playlistID string, trackIDs []string) error
	Delete(ctx context.Context, ownerID, playlistID string) error
}

type PlaylistHandlers struct {
	playlists PlaylistStore
	tokens    *auth.Tokens
	shared    SharedPlaylistStore
	streams   StreamPresigner
	save      SavePolicy
}

func NewPlaylistHandlers(playlists PlaylistStore, tokens *auth.Tokens) *PlaylistHandlers {
	return &PlaylistHandlers{playlists: playlists, tokens: tokens}
}

func (h *PlaylistHandlers) register(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/playlists", h.handleList)
	mux.HandleFunc("POST /api/v1/playlists", h.handleCreate)
	mux.HandleFunc("GET /api/v1/playlists/{id}", h.handleGet)
	mux.HandleFunc("PUT /api/v1/playlists/{id}", h.handleRename)
	mux.HandleFunc("DELETE /api/v1/playlists/{id}", h.handleDelete)
	mux.HandleFunc("PUT /api/v1/playlists/{id}/tracks", h.handleReplaceTracks)
	if h.shared != nil {
		h.registerSharing(mux)
	}
}

type playlistResponse struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	TrackCount int    `json:"trackCount"`
	// ShareToken is set while the playlist is shared; only its owner sees it.
	ShareToken *string `json:"shareToken,omitempty"`
	// Public is whether a shared playlist is listed for everyone.
	Public    bool            `json:"public"`
	Tracks    []trackResponse `json:"tracks,omitempty"`
	CreatedAt time.Time       `json:"createdAt"`
	UpdatedAt time.Time       `json:"updatedAt"`
}

func toPlaylistResponse(playlist store.Playlist, includeTracks bool) playlistResponse {
	response := playlistResponse{
		ID: playlist.ID, Name: playlist.Name, TrackCount: len(playlist.Tracks), ShareToken: playlist.ShareToken,
		Public: playlist.IsPublic, CreatedAt: playlist.CreatedAt.UTC(), UpdatedAt: playlist.UpdatedAt.UTC(),
	}
	if includeTracks {
		response.Tracks = make([]trackResponse, 0, len(playlist.Tracks))
		for _, track := range playlist.Tracks {
			response.Tracks = append(response.Tracks, toTrackResponse(track))
		}
	}
	return response
}

func (h *PlaylistHandlers) handleList(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	playlists, err := h.playlists.ListForOwner(r.Context(), userID)
	if err != nil {
		internalError(w, "list playlists", err)
		return
	}
	response := make([]playlistResponse, 0, len(playlists))
	for _, playlist := range playlists {
		response = append(response, toPlaylistResponse(playlist, false))
	}
	writeJSON(w, http.StatusOK, map[string]any{"playlists": response})
}

func (h *PlaylistHandlers) handleGet(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	playlist, err := h.playlists.ForOwner(r.Context(), userID, r.PathValue("id"))
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "not_found")
		return
	}
	if err != nil {
		internalError(w, "get playlist", err)
		return
	}
	writeJSON(w, http.StatusOK, toPlaylistResponse(playlist, true))
}

type playlistNameRequest struct {
	Name string `json:"name"`
}

func (h *PlaylistHandlers) handleCreate(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	name, ok := decodePlaylistName(w, r)
	if !ok {
		return
	}
	playlist, err := h.playlists.Create(r.Context(), userID, name)
	if err != nil {
		internalError(w, "create playlist", err)
		return
	}
	writeJSON(w, http.StatusCreated, toPlaylistResponse(playlist, false))
}

func (h *PlaylistHandlers) handleRename(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	name, ok := decodePlaylistName(w, r)
	if !ok {
		return
	}
	playlist, err := h.playlists.Rename(r.Context(), userID, r.PathValue("id"), name)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "not_found")
		return
	}
	if err != nil {
		internalError(w, "rename playlist", err)
		return
	}
	writeJSON(w, http.StatusOK, toPlaylistResponse(playlist, false))
}

type replacePlaylistTracksRequest struct {
	TrackIDs []string `json:"trackIds"`
}

func (h *PlaylistHandlers) handleReplaceTracks(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	var input replacePlaylistTracksRequest
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxPlaylistBodyBytes))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil || input.TrackIDs == nil || len(input.TrackIDs) > maxPlaylistTracks {
		writeError(w, http.StatusBadRequest, "invalid_playlist_tracks")
		return
	}
	seen := make(map[string]struct{}, len(input.TrackIDs))
	for _, id := range input.TrackIDs {
		if strings.TrimSpace(id) == "" {
			writeError(w, http.StatusBadRequest, "invalid_playlist_tracks")
			return
		}
		if _, duplicate := seen[id]; duplicate {
			writeError(w, http.StatusBadRequest, "duplicate_track")
			return
		}
		seen[id] = struct{}{}
	}
	if err := h.playlists.ReplaceTracks(r.Context(), userID, r.PathValue("id"), input.TrackIDs); errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "not_found")
		return
	} else if err != nil {
		internalError(w, "replace playlist tracks", err)
		return
	}
	playlist, err := h.playlists.ForOwner(r.Context(), userID, r.PathValue("id"))
	if err != nil {
		internalError(w, "reload playlist", err)
		return
	}
	writeJSON(w, http.StatusOK, toPlaylistResponse(playlist, true))
}

func (h *PlaylistHandlers) handleDelete(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	if err := h.playlists.Delete(r.Context(), userID, r.PathValue("id")); errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "not_found")
		return
	} else if err != nil {
		internalError(w, "delete playlist", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func decodePlaylistName(w http.ResponseWriter, r *http.Request) (string, bool) {
	var input playlistNameRequest
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxPlaylistBodyBytes))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return "", false
	}
	name := strings.TrimSpace(input.Name)
	if name == "" || utf8.RuneCountInString(name) > maxPlaylistNameRunes {
		writeError(w, http.StatusBadRequest, "invalid_playlist_name")
		return "", false
	}
	return name, true
}
