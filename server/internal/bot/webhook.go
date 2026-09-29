package bot

import (
	"context"
	"crypto/subtle"
	"io"
	"log/slog"
	"net/http"
)

const maxUpdateBytes = 1 << 20

// Parser turns a provider's webhook body into an Update. ok is false for
// updates Nafir does not handle, such as edits and channel posts.
type Parser func(body []byte) (u Update, ok bool, err error)

// Webhook serves a provider's webhook. The secret is part of the URL the
// provider was given, so only the provider knows where to post. Each update
// is handled with a bounded number running at once; when all are busy the
// provider is asked to redeliver later.
func Webhook(ctx context.Context, service *Service, parse Parser, secret string, concurrency int) http.Handler {
	slots := make(chan struct{}, concurrency)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if subtle.ConstantTimeCompare([]byte(r.PathValue("secret")), []byte(secret)) != 1 {
			http.NotFound(w, r)
			return
		}
		body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxUpdateBytes))
		if err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		update, ok, err := parse(body)
		if err != nil {
			// A body the provider will keep resending the same way; drop it.
			slog.Warn("bot webhook: unreadable update", "provider", service.provider.Name(), "error", err)
			w.WriteHeader(http.StatusOK)
			return
		}
		if !ok {
			w.WriteHeader(http.StatusOK)
			return
		}
		select {
		case slots <- struct{}{}:
		default:
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
		go func() {
			defer func() { <-slots }()
			if err := service.Handle(ctx, update); err != nil {
				slog.Error("bot update failed", "provider", service.provider.Name(), "error", err)
			}
		}()
	})
}
