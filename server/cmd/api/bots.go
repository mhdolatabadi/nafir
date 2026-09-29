package main

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/bot"
	"github.com/mhdolatabadi/nafir/server/internal/botapi"
	"github.com/mhdolatabadi/nafir/server/internal/httpapi"
	"github.com/mhdolatabadi/nafir/server/internal/storage"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

const (
	defaultBaleAPIURL = "https://tapi.bale.ai"
	// Telegram's Bot API serves bots files up to 20 MB; Bale follows it.
	defaultBotDownloadBytes = 20 << 20
	botWebhookConcurrency   = 16
	minWebhookSecretLength  = 32
)

type botDeps struct {
	tokenSecret []byte
	tokens      *auth.Tokens
	bots        *store.Bots
	users       *store.Users
	tracks      *store.Tracks
	objects     *storage.Storage
	policy      bot.UploadPolicy
}

// setupBots starts every messenger bot with a token configured. It returns
// their webhooks and the app-facing bot endpoints, which list no bots when
// none is configured.
func setupBots(ctx context.Context, deps botDeps) (map[string]http.Handler, *httpapi.BotHandlers, error) {
	linkRate, err := rateLimiterEnv("BOT_LINK_RATE", 10, time.Hour)
	if err != nil {
		return nil, nil, err
	}
	baleToken := os.Getenv("BALE_BOT_TOKEN")
	if baleToken == "" {
		return nil, httpapi.NewBotHandlers(nil, deps.tokens, nil, linkRate), nil
	}
	secret := os.Getenv("BOT_WEBHOOK_SECRET")
	if len(secret) < minWebhookSecretLength || strings.ContainsAny(secret, "/?#% ") {
		return nil, nil, fmt.Errorf("BOT_WEBHOOK_SECRET must be at least %d URL-safe characters", minWebhookSecretLength)
	}
	publicURL := os.Getenv("BOT_PUBLIC_URL")
	if publicURL == "" {
		publicURL = os.Getenv("STORAGE_PUBLIC_URL")
	}
	if parsed, err := url.Parse(publicURL); err != nil || parsed.Scheme != "https" || parsed.Host == "" {
		return nil, nil, fmt.Errorf("BOT_PUBLIC_URL must be the https origin bots post to, got %q", publicURL)
	}
	// Link codes get their own key, derived so AUTH_TOKEN_SECRET stays the
	// only secret to manage.
	mac := hmac.New(sha256.New, deps.tokenSecret)
	mac.Write([]byte("nafir bot link codes"))
	linker, err := bot.NewLinker(deps.bots, mac.Sum(nil), bot.DefaultLinkLimits)
	if err != nil {
		return nil, nil, err
	}
	importer := bot.NewImporter(deps.bots, deps.tracks, deps.objects, deps.policy)

	baleMax, err := positiveInt64Env("BALE_MAX_DOWNLOAD_BYTES", defaultBotDownloadBytes)
	if err != nil {
		return nil, nil, err
	}
	baleURL := os.Getenv("BALE_API_URL")
	if baleURL == "" {
		baleURL = defaultBaleAPIURL
	}
	bale, err := botapi.New(botapi.Config{Name: "bale", BaseURL: baleURL, Token: baleToken, MaxDownloadBytes: baleMax})
	if err != nil {
		return nil, nil, fmt.Errorf("bale: %w", err)
	}
	baleInfo := httpapi.Bot{Provider: "bale", Name: "بله"}
	if username := strings.TrimPrefix(os.Getenv("BALE_BOT_USERNAME"), "@"); username != "" {
		baleInfo.Username = username
		baleInfo.LinkURL = "https://ble.ir/" + url.PathEscape(username) + "?start=%s"
	}

	service := bot.NewService(bale, deps.bots, linker, deps.users, importer)
	webhookURL := strings.TrimSuffix(publicURL, "/") + "/api/v1/bots/bale/webhook/" + secret
	go registerWebhook(ctx, bale, webhookURL)
	go service.Resume(ctx)
	go forgetOldUpdates(ctx, deps.bots)
	slog.Info("Bale bot enabled")
	webhooks := map[string]http.Handler{
		"bale": bot.Webhook(ctx, service, botapi.Parse, secret, botWebhookConcurrency),
	}
	return webhooks, httpapi.NewBotHandlers(linker, deps.tokens, []httpapi.Bot{baleInfo}, linkRate), nil
}

// registerWebhook points the provider at Nafir, retrying while it is unreachable.
func registerWebhook(ctx context.Context, client *botapi.Client, webhookURL string) {
	for attempt := 1; ; attempt++ {
		err := client.SetWebhook(ctx, webhookURL)
		if err == nil {
			slog.Info("bot webhook registered", "provider", client.Name())
			return
		}
		// The URL holds the webhook secret; log only the error, which the
		// client has already stripped of the token.
		slog.Warn("bot webhook registration failed", "provider", client.Name(), "attempt", attempt,
			"error", strings.ReplaceAll(err.Error(), webhookURL, "<webhook>"))
		delay := min(time.Duration(attempt)*10*time.Second, 5*time.Minute)
		select {
		case <-ctx.Done():
			return
		case <-time.After(delay):
		}
	}
}

// forgetOldUpdates keeps the redelivery table small; providers give up
// redelivering within a day.
func forgetOldUpdates(ctx context.Context, bots *store.Bots) {
	ticker := time.NewTicker(time.Hour)
	defer ticker.Stop()
	for {
		if err := bots.ForgetUpdatesBefore(ctx, time.Now().Add(-7*24*time.Hour)); err != nil && !errors.Is(err, context.Canceled) {
			slog.Error("forget old bot updates", "error", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
