package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/bot"
	"github.com/mhdolatabadi/nafir/server/internal/httpapi"
	"github.com/mhdolatabadi/nafir/server/internal/storage"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

const (
	defaultTokenTTL      = 30 * 24 * time.Hour
	defaultStreamURLTTL  = time.Hour
	defaultMaxUpload     = 200 << 20
	defaultOwnerQuota    = 5 << 30
	defaultMaxPending    = 3
	defaultPendingTTL    = 2 * time.Hour
	defaultCleanupEvery  = 10 * time.Minute
	defaultCleanupBatch  = 100
	maxRateLimitKeys     = 10_000
	storageStartupWindow = time.Minute
)

func main() {
	if err := run(); err != nil {
		slog.Error("Nafir API failed", "error", err)
		os.Exit(1)
	}
}

func run() error {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		return errors.New("DATABASE_URL is required")
	}
	tokenTTL := defaultTokenTTL
	if raw := os.Getenv("AUTH_TOKEN_TTL"); raw != "" {
		parsed, err := time.ParseDuration(raw)
		if err != nil {
			return fmt.Errorf("AUTH_TOKEN_TTL: %w", err)
		}
		tokenTTL = parsed
	}
	tokens, err := auth.NewTokens([]byte(os.Getenv("AUTH_TOKEN_SECRET")), tokenTTL)
	if err != nil {
		return fmt.Errorf("AUTH_TOKEN_SECRET: %w", err)
	}

	streamURLTTL := defaultStreamURLTTL
	if raw := os.Getenv("STORAGE_URL_TTL"); raw != "" {
		parsed, err := time.ParseDuration(raw)
		if err != nil {
			return fmt.Errorf("STORAGE_URL_TTL: %w", err)
		}
		streamURLTTL = parsed
	}
	maxUploadBytes, err := positiveInt64Env("MAX_UPLOAD_BYTES", defaultMaxUpload)
	if err != nil {
		return err
	}
	ownerQuotaBytes, err := positiveInt64Env("STORAGE_QUOTA_BYTES", defaultOwnerQuota)
	if err != nil {
		return err
	}
	maxPending, err := positiveIntEnv("MAX_PENDING_UPLOADS", defaultMaxPending)
	if err != nil {
		return err
	}
	pendingTTL, err := positiveDurationEnv("PENDING_UPLOAD_TTL", defaultPendingTTL)
	if err != nil {
		return err
	}
	cleanupEvery, err := positiveDurationEnv("PENDING_CLEANUP_INTERVAL", defaultCleanupEvery)
	if err != nil {
		return err
	}
	cleanupBatch, err := positiveIntEnv("PENDING_CLEANUP_BATCH", defaultCleanupBatch)
	if err != nil {
		return err
	}
	uploadsEnabled := true
	if raw := os.Getenv("UPLOADS_ENABLED"); raw != "" {
		uploadsEnabled, err = strconv.ParseBool(raw)
		if err != nil {
			return fmt.Errorf("UPLOADS_ENABLED must be true or false, got %q", raw)
		}
	}
	objects, err := storage.New(storage.Config{
		Endpoint:  os.Getenv("STORAGE_ENDPOINT"),
		PublicURL: os.Getenv("STORAGE_PUBLIC_URL"),
		AccessKey: os.Getenv("STORAGE_ACCESS_KEY"),
		SecretKey: os.Getenv("STORAGE_SECRET_KEY"),
		Bucket:    os.Getenv("STORAGE_BUCKET"),
		URLTTL:    streamURLTTL,
	})
	if err != nil {
		return fmt.Errorf("storage: %w", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return fmt.Errorf("connect to database: %w", err)
	}
	defer pool.Close()
	if err := store.Migrate(ctx, pool); err != nil {
		return fmt.Errorf("migrate database: %w", err)
	}

	if err := ensureBucket(ctx, objects); err != nil {
		return fmt.Errorf("storage bucket: %w", err)
	}

	registerRate, err := rateLimiterEnv("REGISTER_RATE", 5, time.Hour)
	if err != nil {
		return err
	}
	loginRate, err := rateLimiterEnv("LOGIN_RATE", 30, 15*time.Minute)
	if err != nil {
		return err
	}
	reservationUserRate, err := rateLimiterEnv("UPLOAD_RESERVATION_USER_RATE", 120, 10*time.Minute)
	if err != nil {
		return err
	}
	reservationIPRate, err := rateLimiterEnv("UPLOAD_RESERVATION_IP_RATE", 240, 10*time.Minute)
	if err != nil {
		return err
	}
	completionUserRate, err := rateLimiterEnv("UPLOAD_COMPLETION_USER_RATE", 240, 10*time.Minute)
	if err != nil {
		return err
	}
	completionIPRate, err := rateLimiterEnv("UPLOAD_COMPLETION_IP_RATE", 480, 10*time.Minute)
	if err != nil {
		return err
	}
	authHandlers, err := httpapi.NewAuthHandlers(
		store.NewUsers(pool), auth.Passwords{Cost: 12}, tokens,
		httpapi.AuthRateLimiters{Register: registerRate, Login: loginRate},
	)
	if err != nil {
		return err
	}

	tracks := store.NewTracks(pool)
	webhooks, err := setupBots(ctx, botDeps{
		tokenSecret: []byte(os.Getenv("AUTH_TOKEN_SECRET")),
		bots:        store.NewBots(pool),
		users:       store.NewUsers(pool),
		tracks:      tracks,
		objects:     objects,
		policy: bot.UploadPolicy{
			Enabled: uploadsEnabled, MaxFileBytes: maxUploadBytes,
			MaxOwnerBytes: ownerQuotaBytes, MaxPending: maxPending,
		},
	})
	if err != nil {
		return fmt.Errorf("bots: %w", err)
	}
	server := &http.Server{
		Addr: ":" + port,
		Handler: httpapi.NewHandler(httpapi.Config{
			AllowedOrigin: os.Getenv("WEB_ORIGIN"),
			Auth:          authHandlers,
			Tracks: httpapi.NewTrackHandlers(tracks, objects, tokens, httpapi.UploadLimits{
				MaxFileBytes: maxUploadBytes, MaxOwnerBytes: ownerQuotaBytes,
				MaxPending: maxPending, Enabled: uploadsEnabled,
				ReservationUserRate: reservationUserRate, ReservationIPRate: reservationIPRate,
				CompletionUserRate: completionUserRate, CompletionIPRate: completionIPRate,
			}),
			Playlists: httpapi.NewPlaylistHandlers(store.NewPlaylists(pool), tokens),
			Webhooks:  webhooks,
		}),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	go cleanPendingUploads(ctx, tracks, objects, pendingTTL, cleanupEvery, cleanupBatch)

	serverErr := make(chan error, 1)
	go func() {
		slog.Info("Nafir API started", "address", server.Addr)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErr <- err
		}
	}()

	select {
	case err := <-serverErr:
		return err
	case <-ctx.Done():
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("graceful shutdown: %w", err)
	}
	slog.Info("Nafir API stopped")
	return nil
}

// ensureBucket retries while MinIO is still starting next to the API.
func ensureBucket(ctx context.Context, objects *storage.Storage) error {
	deadline := time.Now().Add(storageStartupWindow)
	for {
		err := objects.EnsureBucket(ctx)
		if err == nil || time.Now().After(deadline) {
			return err
		}
		slog.Warn("storage not ready, retrying", "error", err)
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(2 * time.Second):
		}
	}
}

func positiveInt64Env(name string, fallback int64) (int64, error) {
	raw := os.Getenv(name)
	if raw == "" {
		return fallback, nil
	}
	value, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || value <= 0 {
		return 0, fmt.Errorf("%s must be a positive integer, got %q", name, raw)
	}
	return value, nil
}

func positiveIntEnv(name string, fallback int) (int, error) {
	value, err := positiveInt64Env(name, int64(fallback))
	if err != nil {
		return 0, err
	}
	maxInt := int64(^uint(0) >> 1)
	if value > maxInt {
		return 0, fmt.Errorf("%s is too large", name)
	}
	return int(value), nil
}

func rateLimiterEnv(prefix string, requestsFallback int, windowFallback time.Duration) (*httpapi.RateLimiter, error) {
	requests, err := positiveIntEnv(prefix+"_REQUESTS", requestsFallback)
	if err != nil {
		return nil, err
	}
	window := windowFallback
	if raw := os.Getenv(prefix + "_WINDOW"); raw != "" {
		window, err = time.ParseDuration(raw)
		if err != nil || window <= 0 {
			return nil, fmt.Errorf("%s_WINDOW must be a positive duration, got %q", prefix, raw)
		}
	}
	return httpapi.NewRateLimiter(
		httpapi.RateLimit{Requests: requests, Window: window},
		maxRateLimitKeys,
	), nil
}

func positiveDurationEnv(name string, fallback time.Duration) (time.Duration, error) {
	raw := os.Getenv(name)
	if raw == "" {
		return fallback, nil
	}
	value, err := time.ParseDuration(raw)
	if err != nil || value <= 0 {
		return 0, fmt.Errorf("%s must be a positive duration, got %q", name, raw)
	}
	return value, nil
}

type pendingCleaner interface {
	CleanupStalePending(context.Context, time.Time, int, func(context.Context, string) error) (int, error)
}

type objectRemover interface {
	Remove(context.Context, string) error
}

func cleanPendingUploads(
	ctx context.Context,
	tracks pendingCleaner,
	objects objectRemover,
	lifetime time.Duration,
	interval time.Duration,
	batch int,
) {
	cleanup := func() {
		removed, err := tracks.CleanupStalePending(
			ctx, time.Now().Add(-lifetime), batch, objects.Remove,
		)
		if err != nil {
			if ctx.Err() == nil {
				slog.Error("pending upload cleanup failed", "error", err)
			}
			return
		}
		if removed > 0 {
			slog.Info("pending upload cleanup completed", "removed", removed)
		}
	}

	cleanup()
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			cleanup()
		}
	}
}
