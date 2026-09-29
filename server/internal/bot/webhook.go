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

// WebhookAuth says how a webhook request proves it comes from the provider.
type WebhookAuth struct {
	// PathSecret is part of the URL the provider was given, so only the
	// provider knows where to post.
	PathSecret string
	// Header and HeaderSecret, if set, must also match: providers such as
	// Telegram echo a registered secret in a header of every update.
	Header       string
	HeaderSecret string
}

func (a WebhookAuth) allows(r *http.Request) bool {
	if subtle.ConstantTimeCompare([]byte(r.PathValue("secret")), []byte(a.PathSecret)) != 1 {
		return false
	}
	return a.Header == "" ||
		subtle.ConstantTimeCompare([]byte(r.Header.Get(a.Header)), []byte(a.HeaderSecret)) == 1
}

// Webhook serves a provider's webhook. Each update is handled with a bounded
// number running at once; when all are busy the provider is asked to
// redeliver later.
func Webhook(ctx context.Context, service *Service, parse Parser, auth WebhookAuth, concurrency int) http.Handler {
	slots := make(chan struct{}, concurrency)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !auth.allows(r) {
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
