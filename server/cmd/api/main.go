package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mhdolatabadi/nafir/server/internal/auth"
	"github.com/mhdolatabadi/nafir/server/internal/httpapi"
	"github.com/mhdolatabadi/nafir/server/internal/storage"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

const (
	defaultTokenTTL      = 30 * 24 * time.Hour
	defaultStreamURLTTL  = time.Hour
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

	authHandlers, err := httpapi.NewAuthHandlers(store.NewUsers(pool), auth.Passwords{Cost: 12}, tokens)
	if err != nil {
		return err
	}

	server := &http.Server{
		Addr: ":" + port,
		Handler: httpapi.NewHandler(httpapi.Config{
			AllowedOrigin: os.Getenv("WEB_ORIGIN"),
			Auth:          authHandlers,
			Tracks:        httpapi.NewTrackHandlers(store.NewTracks(pool), objects, tokens),
		}),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

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
