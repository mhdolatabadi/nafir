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
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/bot"
	"github.com/mhdolatabadi/nafir/server/internal/httpapi"
	"github.com/mhdolatabadi/nafir/server/internal/linkimport"
	"github.com/mhdolatabadi/nafir/server/internal/storage"
	"github.com/mhdolatabadi/nafir/server/internal/store"
	"github.com/mhdolatabadi/nafir/server/internal/tagwriter"
)

const (
	defaultTokenTTL      = 30 * 24 * time.Hour
	defaultStreamURLTTL  = time.Hour
	defaultMaxUpload     = 200 << 20
	defaultOwnerQuota    = 1 << 30
	defaultMaxPending    = 3
	defaultPendingTTL    = 2 * time.Hour
	defaultCleanupEvery  = 10 * time.Minute
	defaultCleanupBatch  = 100
	maxRateLimitKeys     = 10_000
	defaultTagWorkers    = 1
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
	tagWorkers, err := positiveIntEnv("TAG_REWRITE_WORKERS", defaultTagWorkers)
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
	// Visitors without an account, per IP: browsing and playing public playlists.
	publicViewRate, err := rateLimiterEnv("PUBLIC_VIEW_RATE", 300, 10*time.Minute)
	if err != nil {
		return err
	}
	publicStreamRate, err := rateLimiterEnv("PUBLIC_STREAM_RATE", 300, 10*time.Minute)
	if err != nil {
		return err
	}
	accountDeleteRate, err := rateLimiterEnv("ACCOUNT_DELETE_RATE", 5, time.Hour)
	if err != nil {
		return err
	}
	users := store.NewUsers(pool)
	authHandlers, err := httpapi.NewAuthHandlers(
		users, auth.Passwords{Cost: 12}, tokens,
		httpapi.AuthRateLimiters{Register: registerRate, Login: loginRate},
	)
	if err != nil {
		return err
	}
	adminEmails := strings.Split(os.Getenv("ADMIN_EMAILS"), ",")
	for _, raw := range adminEmails {
		email := strings.ToLower(strings.TrimSpace(raw))
		if email == "" {
			continue
		}
		if _, _, err := users.ByEmail(ctx, email); err != nil {
			return fmt.Errorf("ADMIN_EMAILS requires existing accounts: %w", err)
		}
	}
	authHandlers.WithAdmins(adminEmails)
	// Uploads handed out before an account is deleted may still land until
	// pending reservations expire, so the purge job sweeps until then.
	authHandlers.WithAccountDeletion(httpapi.AccountDeletion{
		Accounts: users, Objects: objects, Rate: accountDeleteRate, Grace: pendingTTL,
	})

	tracks := store.NewTracks(pool)
	// Rewrites embedded tags after metadata edits. A replaced object stays
	// readable for one stream URL lifetime so playback under way can finish.
	retags := tagwriter.New(tracks, objects, tagwriter.Config{
		Workers: tagWorkers, TempDir: os.Getenv("TAG_REWRITE_TMPDIR"),
		Grace: streamURLTTL + time.Minute, MaxOwnerBytes: ownerQuotaBytes,
	})
	playlists := store.NewPlaylists(pool)
	bots := store.NewBots(pool)
	webhooks, botHandlers, botMonitor, err := setupBots(ctx, botDeps{
		tokenSecret: []byte(os.Getenv("AUTH_TOKEN_SECRET")),
		tokens:      tokens,
		bots:        bots,
		users:       users,
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
	// Imports from song pages and audio links run through the same pipeline,
	// quota and limits as the bots' imports.
	linkImportRate, err := rateLimiterEnv("LINK_IMPORT_USER_RATE", 20, 10*time.Minute)
	if err != nil {
		return err
	}
	linkFetcher := linkimport.NewFetcher()
	linkImports := linkimport.NewService(linkFetcher, linkimport.NewProvider(linkFetcher, maxUploadBytes),
		bot.NewImporter(bots, tracks, objects, bot.UploadPolicy{
			Enabled: uploadsEnabled, MaxFileBytes: maxUploadBytes,
			MaxOwnerBytes: ownerQuotaBytes, MaxPending: maxPending,
		}), bots, maxPending)
	go linkImports.Resume(ctx)

	var ops *httpapi.OpsHandlers
	if opsToken := os.Getenv("OPS_TOKEN"); opsToken != "" {
		if len(opsToken) < 32 {
			return errors.New("OPS_TOKEN must be at least 32 characters")
		}
		var reporter httpapi.BotHealthReporter
		if botMonitor != nil {
			reporter = botMonitor
		}
		ops = httpapi.NewOpsHandlers(opsToken, reporter)
	}
	server := &http.Server{
		Addr: ":" + port,
		Handler: httpapi.NewHandler(httpapi.Config{
			AllowedOrigin: os.Getenv("WEB_ORIGIN"),
			Auth:          authHandlers,
			Admin:         httpapi.NewAdminHandlers(authHandlers, users),
			Tracks: httpapi.NewTrackHandlers(tracks, objects, tokens, httpapi.UploadLimits{
				MaxFileBytes: maxUploadBytes, MaxOwnerBytes: ownerQuotaBytes,
				MaxPending: maxPending, Enabled: uploadsEnabled,
				ReservationUserRate: reservationUserRate, ReservationIPRate: reservationIPRate,
				CompletionUserRate: completionUserRate, CompletionIPRate: completionIPRate,
			}).WithImports(bots).WithTagRewrites(retags),
			Playlists: httpapi.NewPlaylistHandlers(playlists, tokens).WithSharing(playlists, objects, httpapi.SavePolicy{
				Objects: objects, MaxOwnerBytes: ownerQuotaBytes, Enabled: uploadsEnabled,
			}).WithAnonymous(httpapi.AnonymousLimits{View: publicViewRate, Stream: publicStreamRate}),
			Public: httpapi.NewPublicPages(playlists, objects,
				httpapi.AnonymousLimits{View: publicViewRate, Stream: publicStreamRate}).
				WithContact(os.Getenv("PRIVACY_CONTACT_EMAIL")),
			Bots:        botHandlers,
			LinkImports: httpapi.NewLinkImportHandlers(linkImports, tokens, linkImportRate),
			Ops:         ops,
			Webhooks:    webhooks,
		}),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	go retags.Run(ctx)
	go cleanPendingUploads(ctx, tracks, objects, pendingTTL, cleanupEvery, cleanupBatch)
	go purgeDeletedAccounts(ctx, users, objects, cleanupEvery, cleanupBatch)

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

type accountPurgeQueue interface {
	PendingAccountPurges(ctx context.Context, limit int) ([]store.AccountDeletion, error)
	MarkAccountPurged(ctx context.Context, userID string) (bool, error)
}

type prefixRemover interface {
	RemovePrefix(ctx context.Context, prefix string) (int, error)
}

// purgeDeletedAccounts removes what is left in storage of deleted accounts:
// objects the request couldn't remove, and uploads that landed afterwards.
func purgeDeletedAccounts(ctx context.Context, accounts accountPurgeQueue, objects prefixRemover, interval time.Duration, batch int) {
	purgeAccountsOnce(ctx, accounts, objects, batch)
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			purgeAccountsOnce(ctx, accounts, objects, batch)
		}
	}
}

// purgeAccountsOnce sweeps one batch of deleted accounts. An account is
// marked purged only by a sweep after its grace period, so nothing that
// arrives later is missed; a failed sweep is retried on the next run.
func purgeAccountsOnce(ctx context.Context, accounts accountPurgeQueue, objects prefixRemover, batch int) {
	pending, err := accounts.PendingAccountPurges(ctx, batch)
	if err != nil {
		if ctx.Err() == nil {
			slog.Error("deleted account purge failed", "error", err)
		}
		return
	}
	for _, deletion := range pending {
		removed, err := objects.RemovePrefix(ctx, deletion.ObjectPrefix)
		if err != nil {
			if ctx.Err() == nil {
				slog.Error("deleted account objects not removed", "account", deletion.UserID, "error", err)
			}
			continue
		}
		if removed > 0 {
			slog.Info("deleted account objects removed", "account", deletion.UserID, "objects", removed)
		}
		if _, err := accounts.MarkAccountPurged(ctx, deletion.UserID); err != nil && ctx.Err() == nil {
			slog.Error("deleted account purge not recorded", "account", deletion.UserID, "error", err)
		}
	}
}
