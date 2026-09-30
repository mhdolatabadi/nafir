package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/mhdolatabadi/nafir/server/internal/audio"
	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/storage"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

const (
	maxTrackBodyBytes = 4 << 10
	maxTextLength     = 200
)

// TrackStore reads and writes tracks for one owner; *store.Tracks implements it.
type TrackStore interface {
	ListForOwner(ctx context.Context, ownerID string) ([]store.Track, error)
	UsageForOwner(ctx context.Context, ownerID string) (int64, error)
	ForOwner(ctx context.Context, ownerID, trackID string) (store.Track, error)
	ReservePending(ctx context.Context, ownerID string, track store.NewTrack, maxOwnerBytes int64, maxPending int) (store.Track, error)
	MarkReady(ctx context.Context, ownerID, trackID string) (store.Track, error)
	UpdateMetadata(ctx context.Context, ownerID, trackID string, metadata store.TrackMetadata) (store.Track, error)
	Delete(ctx context.Context, ownerID, trackID string) error
}

// ObjectStore is the object storage the track endpoints use; *storage.Storage implements it.
type ObjectStore interface {
	PresignGet(ctx context.Context, key string) (string, time.Time, error)
	PresignUpload(ctx context.Context, key, contentType string, sizeBytes int64) (storage.Upload, error)
	Size(ctx context.Context, key string) (int64, error)
	Head(ctx context.Context, key string, n int64) ([]byte, error)
	Remove(ctx context.Context, key string) error
}

type UploadLimits struct {
	MaxFileBytes        int64
	MaxOwnerBytes       int64
	MaxPending          int
	Enabled             bool
	ReservationUserRate *RateLimiter
	ReservationIPRate   *RateLimiter
	CompletionUserRate  *RateLimiter
	CompletionIPRate    *RateLimiter
}

type TrackHandlers struct {
	tracks  TrackStore
	storage ObjectStore
	tokens  *auth.Tokens
	limits  UploadLimits
	imports ImportCounter
}

func NewTrackHandlers(tracks TrackStore, objects ObjectStore, tokens *auth.Tokens, limits UploadLimits) *TrackHandlers {
	return &TrackHandlers{tracks: tracks, storage: objects, tokens: tokens, limits: limits}
}

func (h *TrackHandlers) register(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/tracks", h.handleList)
	mux.HandleFunc("POST /api/v1/tracks/uploads", h.handleCreateUpload)
	mux.HandleFunc("GET /api/v1/tracks/{id}", h.handleGet)
	mux.HandleFunc("PATCH /api/v1/tracks/{id}", h.handleUpdate)
	mux.HandleFunc("DELETE /api/v1/tracks/{id}", h.handleDelete)
	mux.HandleFunc("POST /api/v1/tracks/{id}/complete", h.handleComplete)
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
	Source      string    `json:"source"`
	CreatedAt   time.Time `json:"createdAt"`
}

func toTrackResponse(t store.Track) trackResponse {
	return trackResponse{
		ID: t.ID, Title: t.Title, Artist: t.Artist, Album: t.Album, DurationMS: t.DurationMS,
		ContentType: t.ContentType, SizeBytes: t.SizeBytes, Source: t.Source, CreatedAt: t.CreatedAt.UTC(),
	}
}

type trackListResponse struct {
	Tracks  []trackResponse      `json:"tracks"`
	Storage storageUsageResponse `json:"storage"`
	// ImportsInProgress counts bot imports not yet in the list, so the app
	// knows to check again soon.
	ImportsInProgress int `json:"importsInProgress"`
}

// ImportCounter counts a user's bot imports still in progress.
type ImportCounter interface {
	ActiveImports(ctx context.Context, userID string) (int, error)
}

// WithImports makes the track list report bot imports in progress.
func (h *TrackHandlers) WithImports(imports ImportCounter) *TrackHandlers {
	h.imports = imports
	return h
}

type storageUsageResponse struct {
	UsedBytes  int64 `json:"usedBytes"`
	LimitBytes int64 `json:"limitBytes"`
}

type streamResponse struct {
	URL       string    `json:"url"`
	ExpiresAt time.Time `json:"expiresAt"`
}

type updateTrackRequest struct {
	Title  *string `json:"title"`
	Artist *string `json:"artist"`
	Album  *string `json:"album"`
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
	usedBytes, err := h.tracks.UsageForOwner(r.Context(), userID)
	if err != nil {
		internalError(w, "read storage usage", err)
		return
	}
	response := trackListResponse{
		Tracks: make([]trackResponse, 0, len(tracks)),
		Storage: storageUsageResponse{
			UsedBytes: usedBytes, LimitBytes: h.limits.MaxOwnerBytes,
		},
	}
	for _, track := range tracks {
		response.Tracks = append(response.Tracks, toTrackResponse(track))
	}
	if h.imports != nil {
		if response.ImportsInProgress, err = h.imports.ActiveImports(r.Context(), userID); err != nil {
			internalError(w, "count bot imports", err)
			return
		}
	}
	writeJSON(w, http.StatusOK, response)
}

func (h *TrackHandlers) handleGet(w http.ResponseWriter, r *http.Request) {
	track, ok := h.readyTrack(w, r)
	if !ok {
		return
	}
	writeJSON(w, http.StatusOK, toTrackResponse(track))
}

func (h *TrackHandlers) handleStream(w http.ResponseWriter, r *http.Request) {
	track, ok := h.readyTrack(w, r)
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

func (h *TrackHandlers) handleUpdate(w http.ResponseWriter, r *http.Request) {
	track, ok := h.readyTrack(w, r)
	if !ok {
		return
	}
	var input updateTrackRequest
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxTrackBodyBytes))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return
	}
	title := optionalText(input.Title)
	if title == nil {
		writeError(w, http.StatusBadRequest, "invalid_metadata")
		return
	}
	artist := optionalText(input.Artist)
	album := optionalText(input.Album)
	if tooLong(title) || tooLong(artist) || tooLong(album) {
		writeError(w, http.StatusBadRequest, "invalid_metadata")
		return
	}
	updated, err := h.tracks.UpdateMetadata(r.Context(), track.OwnerID, track.ID, store.TrackMetadata{
		Title: *title, Artist: artist, Album: album,
	})
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "not_found")
		return
	}
	if err != nil {
		internalError(w, "update track metadata", err)
		return
	}
	writeJSON(w, http.StatusOK, toTrackResponse(updated))
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

// readyTrack is ownedTrack for tracks whose upload has been verified.
func (h *TrackHandlers) readyTrack(w http.ResponseWriter, r *http.Request) (store.Track, bool) {
	track, ok := h.ownedTrack(w, r)
	if ok && track.Status != store.TrackReady {
		writeError(w, http.StatusNotFound, "not_found")
		return store.Track{}, false
	}
	return track, ok
}

type createUploadRequest struct {
	FileName  string  `json:"fileName"`
	SizeBytes int64   `json:"sizeBytes"`
	Title     *string `json:"title"`
	Artist    *string `json:"artist"`
	Album     *string `json:"album"`
}

type uploadForm struct {
	URL       string            `json:"url"`
	Fields    map[string]string `json:"fields"`
	ExpiresAt time.Time         `json:"expiresAt"`
}

type createUploadResponse struct {
	Track  trackResponse `json:"track"`
	Upload uploadForm    `json:"upload"`
}

// handleCreateUpload records a pending track and returns a form that lets the
// client upload exactly the declared file straight to storage.
func (h *TrackHandlers) handleCreateUpload(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok {
		return
	}
	if !enforceRateLimit(w, h.limits.ReservationUserRate, userID) ||
		!enforceRateLimit(w, h.limits.ReservationIPRate, clientIP(r)) {
		return
	}
	var input createUploadRequest
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxTrackBodyBytes))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return
	}
	contentType, ok := audio.ContentType(input.FileName)
	if !ok {
		writeError(w, http.StatusUnsupportedMediaType, "unsupported_format")
		return
	}
	if !h.limits.Enabled {
		writeError(w, http.StatusServiceUnavailable, "uploads_disabled")
		return
	}
	if input.SizeBytes <= 0 || input.SizeBytes > h.limits.MaxFileBytes {
		writeError(w, http.StatusRequestEntityTooLarge, "invalid_size")
		return
	}
	title := optionalText(input.Title)
	if title == nil {
		derived := audio.Title(input.FileName)
		title = &derived
	}
	if tooLong(title) || tooLong(input.Artist) || tooLong(input.Album) {
		writeError(w, http.StatusBadRequest, "invalid_metadata")
		return
	}

	track, err := h.tracks.ReservePending(r.Context(), userID, store.NewTrack{
		Title:       *title,
		Artist:      optionalText(input.Artist),
		Album:       optionalText(input.Album),
		FileName:    audio.SafeFileName(input.FileName),
		ContentType: contentType,
		SizeBytes:   input.SizeBytes,
	}, h.limits.MaxOwnerBytes, h.limits.MaxPending)
	if errors.Is(err, store.ErrQuotaExceeded) {
		writeError(w, http.StatusRequestEntityTooLarge, "quota_exceeded")
		return
	}
	if errors.Is(err, store.ErrTooManyPending) {
		w.Header().Set("Retry-After", "60")
		writeError(w, http.StatusTooManyRequests, "too_many_pending_uploads")
		return
	}
	if err != nil {
		internalError(w, "create track", err)
		return
	}
	upload, err := h.storage.PresignUpload(r.Context(), track.StorageKey, contentType, input.SizeBytes)
	if err != nil {
		_ = h.tracks.Delete(r.Context(), userID, track.ID)
		internalError(w, "presign upload", err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusCreated, createUploadResponse{
		Track:  toTrackResponse(track),
		Upload: uploadForm{URL: upload.URL, Fields: upload.Fields, ExpiresAt: upload.ExpiresAt.UTC()},
	})
}

// handleComplete verifies the uploaded object and makes the track playable.
// An object that is not the declared audio file is deleted with its track.
func (h *TrackHandlers) handleComplete(w http.ResponseWriter, r *http.Request) {
	track, ok := h.ownedTrack(w, r)
	if !ok {
		return
	}
	if !enforceRateLimit(w, h.limits.CompletionUserRate, track.OwnerID) ||
		!enforceRateLimit(w, h.limits.CompletionIPRate, clientIP(r)) {
		return
	}
	if track.Status == store.TrackReady {
		writeJSON(w, http.StatusOK, toTrackResponse(track))
		return
	}
	size, err := h.storage.Size(r.Context(), track.StorageKey)
	if errors.Is(err, storage.ErrObjectMissing) {
		writeError(w, http.StatusConflict, "upload_missing")
		return
	}
	if err != nil {
		internalError(w, "stat upload", err)
		return
	}
	header, err := h.storage.Head(r.Context(), track.StorageKey, audio.HeaderBytes)
	if err != nil {
		internalError(w, "read upload", err)
		return
	}
	if size != track.SizeBytes || !audio.Matches(track.StorageKey, header) {
		h.discard(r.Context(), track)
		writeError(w, http.StatusUnprocessableEntity, "invalid_audio")
		return
	}
	ready, err := h.tracks.MarkReady(r.Context(), track.OwnerID, track.ID)
	if err != nil {
		internalError(w, "mark track ready", err)
		return
	}
	writeJSON(w, http.StatusOK, toTrackResponse(ready))
}

// handleDelete removes one of the caller's tracks, pending or ready, and its object.
func (h *TrackHandlers) handleDelete(w http.ResponseWriter, r *http.Request) {
	track, ok := h.ownedTrack(w, r)
	if !ok {
		return
	}
	if err := h.storage.Remove(r.Context(), track.StorageKey); err != nil {
		internalError(w, "remove object", err)
		return
	}
	if err := h.tracks.Delete(r.Context(), track.OwnerID, track.ID); err != nil && !errors.Is(err, store.ErrNotFound) {
		internalError(w, "delete track", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *TrackHandlers) discard(ctx context.Context, track store.Track) {
	if err := h.storage.Remove(ctx, track.StorageKey); err != nil {
		slog.Error("remove rejected upload", "track", track.ID, "error", err)
	}
	if err := h.tracks.Delete(ctx, track.OwnerID, track.ID); err != nil {
		slog.Error("delete rejected track", "track", track.ID, "error", err)
	}
}

func optionalText(value *string) *string {
	if value == nil {
		return nil
	}
	trimmed := strings.TrimSpace(*value)
	if trimmed == "" {
		return nil
	}
	return &trimmed
}

func tooLong(value *string) bool {
	return value != nil && utf8.RuneCountInString(strings.TrimSpace(*value)) > maxTextLength
}
