package httpapi

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

// TrackStore reads tracks for one owner; *store.Tracks implements it.
type TrackStore interface {
	ListForOwner(ctx context.Context, ownerID string) ([]store.Track, error)
	ForOwner(ctx context.Context, ownerID, trackID string) (store.Track, error)
}

// Presigner issues short-lived read URLs; *storage.Storage implements it.
type Presigner interface {
	PresignGet(ctx context.Context, key string) (string, time.Time, error)
}

type TrackHandlers struct {
	tracks  TrackStore
	storage Presigner
	tokens  *auth.Tokens
}

func NewTrackHandlers(tracks TrackStore, storage Presigner, tokens *auth.Tokens) *TrackHandlers {
	return &TrackHandlers{tracks: tracks, storage: storage, tokens: tokens}
}

func (h *TrackHandlers) register(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/tracks", h.handleList)
	mux.HandleFunc("GET /api/v1/tracks/{id}", h.handleGet)
	mux.HandleFunc("GET /api/v1/tracks/{id}/stream", h.handleStream)
}

type trackResponse struct {
	ID          string    `json:"id"`
	Title       string    `json:"title"`
	Artist      *string   `json:"artist"`
	Album       *string   `json:"album"`
	DurationMS  *int32    `json:"durationMs"`
	ContentType string    `json:"contentType"`
	SizeBytes   int64     `json:"sizeBytes"`
	CreatedAt   time.Time `json:"createdAt"`
}

func toTrackResponse(t store.Track) trackResponse {
	return trackResponse{
		ID: t.ID, Title: t.Title, Artist: t.Artist, Album: t.Album, DurationMS: t.DurationMS,
		ContentType: t.ContentType, SizeBytes: t.SizeBytes, CreatedAt: t.CreatedAt.UTC(),
	}
}

type trackListResponse struct {
	Tracks []trackResponse `json:"tracks"`
}

type streamResponse struct {
	URL       string    `json:"url"`
	ExpiresAt time.Time `json:"expiresAt"`
}

func (h *TrackHandlers) handleList(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	tracks, err := h.tracks.ListForOwner(r.Context(), userID)
	if err != nil {
		internalError(w, "list tracks", err)
		return
	}
	response := trackListResponse{Tracks: make([]trackResponse, 0, len(tracks))}
	for _, track := range tracks {
		response.Tracks = append(response.Tracks, toTrackResponse(track))
	}
	writeJSON(w, http.StatusOK, response)
}

func (h *TrackHandlers) handleGet(w http.ResponseWriter, r *http.Request) {
	track, ok := h.ownedTrack(w, r)
	if !ok {
		return
	}
	writeJSON(w, http.StatusOK, toTrackResponse(track))
}

func (h *TrackHandlers) handleStream(w http.ResponseWriter, r *http.Request) {
	track, ok := h.ownedTrack(w, r)
	if !ok {
		return
	}
	url, expiresAt, err := h.storage.PresignGet(r.Context(), track.StorageKey)
	if err != nil {
		internalError(w, "presign track", err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, streamResponse{URL: url, ExpiresAt: expiresAt.UTC()})
}

// ownedTrack loads the {id} track for the authenticated user. Another user's
// track is reported as not found, exactly like a missing one.
func (h *TrackHandlers) ownedTrack(w http.ResponseWriter, r *http.Request) (store.Track, bool) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return store.Track{}, false
	}
	track, err := h.tracks.ForOwner(r.Context(), userID, r.PathValue("id"))
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "not_found")
		return store.Track{}, false
	}
	if err != nil {
		internalError(w, "find track", err)
		return store.Track{}, false
	}
	if track.OwnerID != userID {
		// Defence in depth: the store already filters by owner.
		writeError(w, http.StatusNotFound, "not_found")
		return store.Track{}, false
	}
	return track, true
}
