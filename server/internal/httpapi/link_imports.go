package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/linkimport"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

// LinkImporter adds music from links: a song page or an audio file.
type LinkImporter interface {
	Preview(ctx context.Context, userID, rawURL string) ([]linkimport.Candidate, error)
	Submit(ctx context.Context, userID, rawURL string) (store.BotImport, error)
	Recent(ctx context.Context, userID string) ([]store.BotImport, error)
}

// SpotifyImporter builds a playlist from a Spotify link's titles found in
// the user's library.
type SpotifyImporter interface {
	Import(ctx context.Context, userID, rawURL string) (linkimport.SpotifyResult, error)
}

type LinkImportHandlers struct {
	importer LinkImporter
	spotify  SpotifyImporter
	tokens   *auth.Tokens
	// rate bounds how often one user may submit links: each one makes the
	// server fetch a page.
	rate *RateLimiter
	// emailGate keeps unverified accounts from importing into their
	// storage; nil allows everyone.
	emailGate *EmailGate
}

// WithEmailGate keeps accounts with an unverified email out of what costs
// storage or reaches other people.
func (h *LinkImportHandlers) WithEmailGate(gate *EmailGate) *LinkImportHandlers {
	h.emailGate = gate
	return h
}

func NewLinkImportHandlers(importer LinkImporter, tokens *auth.Tokens, rate *RateLimiter) *LinkImportHandlers {
	return &LinkImportHandlers{importer: importer, tokens: tokens, rate: rate}
}

// WithSpotify turns on playlists from Spotify links.
func (h *LinkImportHandlers) WithSpotify(spotify SpotifyImporter) *LinkImportHandlers {
	h.spotify = spotify
	return h
}

func (h *LinkImportHandlers) register(mux *http.ServeMux) {
	if h.spotify != nil {
		mux.HandleFunc("POST /api/v1/imports/spotify", h.handleSpotify)
	}
	mux.HandleFunc("POST /api/v1/imports/link/preview", h.handlePreview)
	mux.HandleFunc("POST /api/v1/imports/link", h.handleSubmit)
	mux.HandleFunc("GET /api/v1/imports/link", h.handleList)
}

type linkImportResponse struct {
	ID       string `json:"id"`
	FileName string `json:"fileName"`
	// Site is the host the file comes from; the link itself is not echoed.
	Site      string    `json:"site"`
	State     string    `json:"state"`
	Error     *string   `json:"error,omitempty"`
	TrackID   *string   `json:"trackId,omitempty"`
	CreatedAt time.Time `json:"createdAt"`
}

func toLinkImportResponse(i store.BotImport) linkImportResponse {
	site := ""
	if u, err := url.Parse(i.FileID); err == nil {
		site = u.Hostname()
	}
	return linkImportResponse{
		ID: i.ID, FileName: i.FileName, Site: site, State: string(i.State),
		Error: i.Error, TrackID: i.TrackID, CreatedAt: i.CreatedAt.UTC(),
	}
}

type linkImportCandidateResponse struct {
	URL             string `json:"url"`
	FileName        string `json:"fileName"`
	Site            string `json:"site"`
	SizeBytes       int64  `json:"sizeBytes,omitempty"`
	Title           string `json:"title,omitempty"`
	Artist          string `json:"artist,omitempty"`
	ThumbnailURL    string `json:"thumbnailUrl,omitempty"`
	DurationSeconds int64  `json:"durationSeconds,omitempty"`
}

func toLinkImportCandidateResponse(c linkimport.Candidate) linkImportCandidateResponse {
	site := ""
	if c.URL != nil {
		site = c.URL.Hostname()
	}
	return linkImportCandidateResponse{
		URL: c.URL.String(), FileName: c.FileName, Site: site, SizeBytes: c.SizeBytes,
		Title: c.Title, Artist: c.Artist, ThumbnailURL: c.Thumbnail, DurationSeconds: int64(c.Duration / time.Second),
	}
}

func (h *LinkImportHandlers) handlePreview(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	if h.rate != nil && !enforceRateLimit(w, h.rate, userID) {
		return
	}
	if !h.emailGate.allow(w, r, userID) {
		return
	}
	var input struct {
		URL string `json:"url"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return
	}
	candidates, err := h.importer.Preview(r.Context(), userID, input.URL)
	switch {
	case writeLinkImportError(w, err):
	case err != nil:
		internalError(w, "preview link import", err)
	default:
		response := make([]linkImportCandidateResponse, 0, len(candidates))
		for _, c := range candidates {
			response = append(response, toLinkImportCandidateResponse(c))
		}
		w.Header().Set("Cache-Control", "no-store")
		writeJSON(w, http.StatusOK, map[string]any{"candidates": response})
	}
}

func (h *LinkImportHandlers) handleSubmit(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	if h.rate != nil && !enforceRateLimit(w, h.rate, userID) {
		return
	}
	if !h.emailGate.allow(w, r, userID) {
		return
	}
	var input struct {
		URL string `json:"url"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return
	}
	job, err := h.importer.Submit(r.Context(), userID, input.URL)
	switch {
	case writeLinkImportError(w, err):
	case err != nil:
		internalError(w, "import from link", err)
	default:
		writeJSON(w, http.StatusAccepted, toLinkImportResponse(job))
	}
}

// writeLinkImportError answers a refused link and reports whether err was
// one. Any other error is left to the caller.
func writeLinkImportError(w http.ResponseWriter, err error) bool {
	switch {
	case errors.Is(err, linkimport.ErrInvalidURL):
		writeError(w, http.StatusBadRequest, "invalid_url")
	case errors.Is(err, linkimport.ErrBlocked):
		writeError(w, http.StatusBadRequest, "blocked_url")
	case errors.Is(err, linkimport.ErrUnreachable):
		writeError(w, http.StatusBadGateway, "unreachable")
	case errors.Is(err, linkimport.ErrNoAudio):
		writeError(w, http.StatusUnprocessableEntity, "no_audio")
	case errors.Is(err, linkimport.ErrNoTracks):
		writeError(w, http.StatusUnprocessableEntity, "no_tracks")
	case errors.Is(err, linkimport.ErrTooLong):
		writeError(w, http.StatusUnprocessableEntity, "too_long")
	case errors.Is(err, linkimport.ErrMetadataOnly):
		writeError(w, http.StatusUnprocessableEntity, "metadata_only")
	case errors.Is(err, linkimport.ErrUnsupported):
		writeError(w, http.StatusUnsupportedMediaType, "unsupported_format")
	case errors.Is(err, linkimport.ErrTooLarge):
		writeError(w, http.StatusRequestEntityTooLarge, "too_large")
	case errors.Is(err, linkimport.ErrDuplicate):
		writeError(w, http.StatusConflict, "duplicate_import")
	case errors.Is(err, linkimport.ErrTooMany):
		writeError(w, http.StatusTooManyRequests, "too_many_imports")
	case errors.Is(err, linkimport.ErrDisabled):
		writeError(w, http.StatusServiceUnavailable, "uploads_disabled")
	default:
		return false
	}
	return true
}

func (h *LinkImportHandlers) handleList(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	imports, err := h.importer.Recent(r.Context(), userID)
	if err != nil {
		internalError(w, "list link imports", err)
		return
	}
	response := make([]linkImportResponse, 0, len(imports))
	for _, i := range imports {
		response = append(response, toLinkImportResponse(i))
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, map[string]any{"imports": response})
}

type spotifyItemResponse struct {
	Title   string   `json:"title"`
	Artists []string `json:"artists"`
	TrackID string   `json:"trackId,omitempty"`
}

func toSpotifyItemResponse(item linkimport.SpotifyItem, trackID string) spotifyItemResponse {
	artists := item.Artists
	if artists == nil {
		artists = []string{}
	}
	return spotifyItemResponse{Title: item.Title, Artists: artists, TrackID: trackID}
}

// handleSpotify matches a Spotify link's titles against the library and
// makes a playlist of the ones found. Nothing is downloaded from Spotify.
func (h *LinkImportHandlers) handleSpotify(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	if h.rate != nil && !enforceRateLimit(w, h.rate, userID) {
		return
	}
	var input struct {
		URL string `json:"url"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return
	}
	result, err := h.spotify.Import(r.Context(), userID, input.URL)
	switch {
	case writeLinkImportError(w, err):
		return
	case err != nil:
		internalError(w, "import spotify link", err)
		return
	}
	matched := make([]spotifyItemResponse, 0, len(result.Matched))
	for _, m := range result.Matched {
		matched = append(matched, toSpotifyItemResponse(m.Item, m.TrackID))
	}
	missing := make([]spotifyItemResponse, 0, len(result.Missing))
	for _, item := range result.Missing {
		missing = append(missing, toSpotifyItemResponse(item, ""))
	}
	response := map[string]any{"name": result.Name, "matched": matched, "missing": missing}
	if result.Playlist != nil {
		response["playlistId"] = result.Playlist.ID
	}
	status := http.StatusOK
	if result.Playlist != nil {
		status = http.StatusCreated
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, status, response)
}
