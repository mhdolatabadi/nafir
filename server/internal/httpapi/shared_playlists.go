package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"net/http"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/bot"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

// shareTokenBytes of randomness make a link nobody can guess.
const shareTokenBytes = 16

// SharedPlaylistStore is what sharing needs from playlists.
type SharedPlaylistStore interface {
	Share(ctx context.Context, ownerID, playlistID, token string) (store.Playlist, error)
	Unshare(ctx context.Context, ownerID, playlistID string) error
	ForShareToken(ctx context.Context, token string) (store.SharedPlaylist, error)
	SharedTrack(ctx context.Context, token, trackID string) (store.Track, error)
}

// StreamPresigner hands out short-lived playback URLs.
type StreamPresigner interface {
	PresignGet(ctx context.Context, key string) (string, time.Time, error)
}

// WithSharing serves playlist sharing: owners turn a playlist's link on and
// off, and anyone signed in who has the link can view it and play its tracks.
func (h *PlaylistHandlers) WithSharing(shared SharedPlaylistStore, streams StreamPresigner) *PlaylistHandlers {
	h.shared, h.streams = shared, streams
	return h
}

func (h *PlaylistHandlers) registerSharing(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/playlists/{id}/share", h.handleShare)
	mux.HandleFunc("DELETE /api/v1/playlists/{id}/share", h.handleUnshare)
	mux.HandleFunc("GET /api/v1/shared-playlists/{token}", h.handleShared)
	mux.HandleFunc("GET /api/v1/shared-playlists/{token}/tracks/{trackId}/stream", h.handleSharedStream)
}

type shareResponse struct {
	ShareToken string `json:"shareToken"`
}

func (h *PlaylistHandlers) handleShare(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	for range 3 {
		token, err := newShareToken()
		if err != nil {
			internalError(w, "draw share token", err)
			return
		}
		playlist, err := h.shared.Share(r.Context(), userID, r.PathValue("id"), token)
		switch {
		case errors.Is(err, store.ErrShareTokenTaken):
			continue
		case errors.Is(err, store.ErrNotFound):
			writeError(w, http.StatusNotFound, "not_found")
		case err != nil:
			internalError(w, "share playlist", err)
		default:
			writeJSON(w, http.StatusOK, shareResponse{ShareToken: *playlist.ShareToken})
		}
		return
	}
	internalError(w, "share playlist", errors.New("could not draw an unused share token"))
}

func (h *PlaylistHandlers) handleUnshare(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	err := h.shared.Unshare(r.Context(), userID, r.PathValue("id"))
	switch {
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "not_found")
	case err != nil:
		internalError(w, "unshare playlist", err)
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}

type sharedPlaylistResponse struct {
	Name       string          `json:"name"`
	Owner      string          `json:"owner"`
	IsOwner    bool            `json:"isOwner"`
	TrackCount int             `json:"trackCount"`
	Tracks     []trackResponse `json:"tracks"`
	UpdatedAt  time.Time       `json:"updatedAt"`
}

// sharedPlaylist loads the playlist for the {token} link. Malformed,
// unknown and unshared links are all the same 404.
func (h *PlaylistHandlers) sharedPlaylist(w http.ResponseWriter, r *http.Request) (store.SharedPlaylist, bool) {
	token := r.PathValue("token")
	if !validShareToken(token) {
		writeError(w, http.StatusNotFound, "not_found")
		return store.SharedPlaylist{}, false
	}
	shared, err := h.shared.ForShareToken(r.Context(), token)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "not_found")
		return store.SharedPlaylist{}, false
	}
	if err != nil {
		internalError(w, "load shared playlist", err)
		return store.SharedPlaylist{}, false
	}
	return shared, true
}

func (h *PlaylistHandlers) handleShared(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	shared, ok := h.sharedPlaylist(w, r)
	if !ok {
		return
	}
	response := sharedPlaylistResponse{
		Name: shared.Name, Owner: bot.MaskEmail(shared.OwnerEmail), IsOwner: shared.OwnerID == userID,
		TrackCount: len(shared.Tracks), Tracks: make([]trackResponse, 0, len(shared.Tracks)),
		UpdatedAt: shared.UpdatedAt.UTC(),
	}
	for _, track := range shared.Tracks {
		response.Tracks = append(response.Tracks, toTrackResponse(track))
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, response)
}

func (h *PlaylistHandlers) handleSharedStream(w http.ResponseWriter, r *http.Request) {
	if _, ok := authenticate(h.tokens, w, r); !ok {
		return
	}
	token := r.PathValue("token")
	if !validShareToken(token) {
		writeError(w, http.StatusNotFound, "not_found")
		return
	}
	track, err := h.shared.SharedTrack(r.Context(), token, r.PathValue("trackId"))
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "not_found")
		return
	}
	if err != nil {
		internalError(w, "load shared track", err)
		return
	}
	url, expiresAt, err := h.streams.PresignGet(r.Context(), track.StorageKey)
	if err != nil {
		internalError(w, "presign shared track", err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, streamResponse{URL: url, ExpiresAt: expiresAt.UTC()})
}

func newShareToken() (string, error) {
	b := make([]byte, shareTokenBytes)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func validShareToken(token string) bool {
	b, err := base64.RawURLEncoding.DecodeString(token)
	return err == nil && len(b) == shareTokenBytes
}
