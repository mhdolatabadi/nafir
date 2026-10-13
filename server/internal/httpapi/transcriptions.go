package httpapi

import (
	"errors"
	"net/http"

	"github.com/mhdolatabadi/nafir/server/internal/transcription"
)

func (h *LyricsHandlers) handleTranscription(w http.ResponseWriter, r *http.Request) {
	track, ok := h.ownTrack(w, r)
	if !ok {
		return
	}
	if h.Transcriptions == nil {
		writeError(w, http.StatusServiceUnavailable, "transcription_disabled")
		return
	}
	if r.Method == http.MethodPost {
		if track.SizeBytes > transcription.MaxFileBytes {
			writeError(w, http.StatusRequestEntityTooLarge, "transcription_too_large")
			return
		}
		err := h.Transcriptions.Queue(r.Context(), track.OwnerID, track.ID)
		if errors.Is(err, transcription.ErrBusy) {
			writeError(w, http.StatusTooManyRequests, "transcription_busy")
			return
		}
		if err != nil {
			internalError(w, "queue transcription", err)
			return
		}
	}
	result, err := h.Transcriptions.Status(r.Context(), track.ID)
	if err != nil {
		internalError(w, "read transcription", err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	status := http.StatusOK
	if r.Method == http.MethodPost {
		status = http.StatusAccepted
	}
	writeJSON(w, status, result)
}
