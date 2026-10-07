package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/lyrics"
	"github.com/mhdolatabadi/nafir/server/internal/store"
	"github.com/mhdolatabadi/nafir/server/internal/transcription"
)

const (
	maxLyricsSearchLength = 200
	maxLyricsBodyBytes    = 1 << 10
	// maxDurationMS is longer than any song; a larger length is ignored.
	maxDurationMS = 24 * 60 * 60 * 1000
)

// LyricsService finds lyrics; *lyrics.Service implements it.
type LyricsService interface {
	ForSong(ctx context.Context, song lyrics.Song) (lyrics.Entry, error)
	Candidates(ctx context.Context, q lyrics.Query, text string) ([]lyrics.Record, error)
	Choose(ctx context.Context, song lyrics.Song, id int64) (lyrics.Entry, error)
}

// OwnedTracks finds a user's own track; *store.Tracks implements it.
type OwnedTracks interface {
	ForOwner(ctx context.Context, ownerID, trackID string) (store.Track, error)
}

// PlayableTracks finds a track someone may play through a playlist;
// *store.Playlists implements it.
type PlayableTracks interface {
	PlaylistTrack(ctx context.Context, userID, playlistID, trackID string) (store.Track, error)
	SharedTrack(ctx context.Context, token, trackID string, publicOnly bool) (store.Track, error)
}

// LyricsLimits caps lyrics requests per signed-in user, and per IP address
// for visitors without an account on public playlists.
type LyricsLimits struct {
	User *RateLimiter
	IP   *RateLimiter
}

// LyricsHandlers serve a track's lyrics to whoever may play it: its owner,
// the members of a collaborative playlist it is in, and people with the
// link of a playlist it is shared in. Only the owner may correct a match.
type LyricsHandlers struct {
	Transcriptions transcription.Store
	service        LyricsService
	owned          OwnedTracks
	playlists      PlayableTracks
	tokens         *auth.Tokens
	limits         LyricsLimits
}

func NewLyricsHandlers(service LyricsService, owned OwnedTracks, playlists PlayableTracks, tokens *auth.Tokens, limits LyricsLimits) *LyricsHandlers {
	return &LyricsHandlers{service: service, owned: owned, playlists: playlists, tokens: tokens, limits: limits}
}

func (h *LyricsHandlers) register(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/tracks/{id}/transcription", h.handleTranscription)
	mux.HandleFunc("POST /api/v1/tracks/{id}/transcription", h.handleTranscription)
	mux.HandleFunc("GET /api/v1/tracks/{id}/lyrics", h.handleOwn)
	mux.HandleFunc("GET /api/v1/tracks/{id}/lyrics/candidates", h.handleCandidates)
	mux.HandleFunc("PUT /api/v1/tracks/{id}/lyrics", h.handleChoose)
	mux.HandleFunc("GET /api/v1/playlists/{id}/tracks/{trackId}/lyrics", h.handlePlaylist)
	mux.HandleFunc("GET /api/v1/shared-playlists/{token}/tracks/{trackId}/lyrics", h.handleShared)
}

// lyricsMatchResponse names the LRCLIB entry the lyrics come from, so the
// listener can tell a wrong match.
type lyricsMatchResponse struct {
	ID         int64  `json:"id"`
	TrackName  string `json:"trackName"`
	ArtistName string `json:"artistName"`
	AlbumName  string `json:"albumName"`
	DurationMS int64  `json:"durationMs"`
	Synced     bool   `json:"synced"`
}

type lyricsResponse struct {
	// Status is found, instrumental or not_found.
	Status string `json:"status"`
	// Synced is LRC text, one "[mm:ss.xx] line" per line.
	Synced *string              `json:"synced"`
	Plain  *string              `json:"plain"`
	Match  *lyricsMatchResponse `json:"match"`
	// Chosen is set when the owner picked this match by hand.
	Chosen bool `json:"chosen"`
	// CanChoose says whether the caller may pick another match.
	CanChoose bool `json:"canChoose"`
}

type lyricsCandidatesResponse struct {
	Candidates []lyricsMatchResponse `json:"candidates"`
}

type chooseLyricsRequest struct {
	LRCLIBID int64 `json:"lrclibId"`
}

func toMatchResponse(r lyrics.Record) lyricsMatchResponse {
	return lyricsMatchResponse{
		ID: r.ID, TrackName: r.TrackName, ArtistName: r.ArtistName, AlbumName: r.AlbumName,
		DurationMS: int64(r.Duration * 1000), Synced: r.SyncedLyrics != nil,
	}
}

func toLyricsResponse(e lyrics.Entry, canChoose bool) lyricsResponse {
	response := lyricsResponse{Status: "not_found", Chosen: e.Chosen, CanChoose: canChoose}
	if !e.Found {
		return response
	}
	match := toMatchResponse(e.Record)
	response.Match = &match
	response.Synced, response.Plain = e.Record.SyncedLyrics, e.Record.PlainLyrics
	switch {
	case e.Record.SyncedLyrics != nil || e.Record.PlainLyrics != nil:
		response.Status = "found"
	case e.Record.Instrumental:
		response.Status = "instrumental"
	}
	return response
}

// songFor is the lookup for track. The app may say how long the track
// plays, which helps matching when the server doesn't know it.
func songFor(r *http.Request, track store.Track) lyrics.Song {
	q := lyrics.Query{Title: track.Title}
	if track.Artist != nil {
		q.Artist = *track.Artist
	}
	if track.Album != nil {
		q.Album = *track.Album
	}
	if track.DurationMS != nil && *track.DurationMS > 0 {
		q.Duration = time.Duration(*track.DurationMS) * time.Millisecond
	} else if ms, err := strconv.ParseInt(r.URL.Query().Get("durationMs"), 10, 64); err == nil && ms > 0 && ms <= maxDurationMS {
		q.Duration = time.Duration(ms) * time.Millisecond
	}
	return lyrics.Song{TrackID: track.ID, Query: q}
}

// ownTrack loads the caller's own ready {id} track, within the rate limit.
func (h *LyricsHandlers) ownTrack(w http.ResponseWriter, r *http.Request) (store.Track, bool) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok || !enforceRateLimit(w, h.limits.User, userID) {
		return store.Track{}, false
	}
	track, err := h.owned.ForOwner(r.Context(), userID, r.PathValue("id"))
	return h.checkTrack(w, track, err, userID)
}

func (h *LyricsHandlers) checkTrack(w http.ResponseWriter, track store.Track, err error, ownerID string) (store.Track, bool) {
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "not_found")
		return store.Track{}, false
	}
	if err != nil {
		internalError(w, "find track for lyrics", err)
		return store.Track{}, false
	}
	if track.Status != store.TrackReady || (ownerID != "" && track.OwnerID != ownerID) {
		writeError(w, http.StatusNotFound, "not_found")
		return store.Track{}, false
	}
	return track, true
}

func (h *LyricsHandlers) handleOwn(w http.ResponseWriter, r *http.Request) {
	track, ok := h.ownTrack(w, r)
	if !ok {
		return
	}
	h.serve(w, r, track, true)
}

// handlePlaylist serves the lyrics of a track in a collaborative playlist
// the caller owns or has joined.
func (h *LyricsHandlers) handlePlaylist(w http.ResponseWriter, r *http.Request) {
	userID, ok := authenticate(h.tokens, w, r)
	if !ok || !enforceRateLimit(w, h.limits.User, userID) {
		return
	}
	track, err := h.playlists.PlaylistTrack(r.Context(), userID, r.PathValue("id"), r.PathValue("trackId"))
	if track, ok = h.checkTrack(w, track, err, ""); ok {
		h.serve(w, r, track, track.OwnerID == userID)
	}
}

// handleShared serves the lyrics of a track in a playlist shared by link;
// without an account, only in a public one.
func (h *LyricsHandlers) handleShared(w http.ResponseWriter, r *http.Request) {
	userID, ok := optionalUser(h.tokens, w, r)
	if !ok {
		return
	}
	if userID != "" {
		ok = enforceRateLimit(w, h.limits.User, userID)
	} else {
		ok = enforceRateLimit(w, h.limits.IP, clientIP(r))
	}
	if !ok {
		return
	}
	token := r.PathValue("token")
	if !validShareToken(token) {
		writeError(w, http.StatusNotFound, "not_found")
		return
	}
	track, err := h.playlists.SharedTrack(r.Context(), token, r.PathValue("trackId"), userID == "")
	if track, ok = h.checkTrack(w, track, err, ""); ok {
		h.serve(w, r, track, userID != "" && track.OwnerID == userID)
	}
}

func (h *LyricsHandlers) serve(w http.ResponseWriter, r *http.Request, track store.Track, canChoose bool) {
	entry, err := h.service.ForSong(r.Context(), songFor(r, track))
	if errors.Is(err, lyrics.ErrUnavailable) {
		writeUnavailable(w)
		return
	}
	if err != nil {
		internalError(w, "find lyrics", err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, toLyricsResponse(entry, canChoose))
}

// handleCandidates lists other LRCLIB entries the owner may pick, for the
// track itself or for the free text in q.
func (h *LyricsHandlers) handleCandidates(w http.ResponseWriter, r *http.Request) {
	track, ok := h.ownTrack(w, r)
	if !ok {
		return
	}
	text := strings.TrimSpace(r.URL.Query().Get("q"))
	if utf8.RuneCountInString(text) > maxLyricsSearchLength || !validText(&text, maxLyricsSearchLength) {
		writeError(w, http.StatusBadRequest, "invalid_query")
		return
	}
	records, err := h.service.Candidates(r.Context(), songFor(r, track).Query, text)
	if errors.Is(err, lyrics.ErrUnavailable) {
		writeUnavailable(w)
		return
	}
	if err != nil {
		internalError(w, "search lyrics", err)
		return
	}
	response := lyricsCandidatesResponse{Candidates: make([]lyricsMatchResponse, 0, len(records))}
	for _, record := range records {
		response.Candidates = append(response.Candidates, toMatchResponse(record))
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, response)
}

// handleChoose makes the LRCLIB entry the owner picked the track's lyrics.
func (h *LyricsHandlers) handleChoose(w http.ResponseWriter, r *http.Request) {
	track, ok := h.ownTrack(w, r)
	if !ok {
		return
	}
	var input chooseLyricsRequest
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxLyricsBodyBytes))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil || input.LRCLIBID <= 0 {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return
	}
	entry, err := h.service.Choose(r.Context(), songFor(r, track), input.LRCLIBID)
	if errors.Is(err, lyrics.ErrNotFound) {
		writeError(w, http.StatusNotFound, "lyrics_not_found")
		return
	}
	if errors.Is(err, lyrics.ErrUnavailable) {
		writeUnavailable(w)
		return
	}
	if err != nil {
		internalError(w, "choose lyrics", err)
		return
	}
	writeJSON(w, http.StatusOK, toLyricsResponse(entry, true))
}

func writeUnavailable(w http.ResponseWriter) {
	w.Header().Set("Retry-After", "30")
	writeError(w, http.StatusServiceUnavailable, "lyrics_unavailable")
}
