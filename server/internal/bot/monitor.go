package bot

import (
	"context"
	"log/slog"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/store"
)

// WebhookStatus is what a provider reports about Nafir's webhook.
type WebhookStatus struct {
	Registered       bool       `json:"registered"`
	MatchesExpected  bool       `json:"matchesExpected"`
	PendingUpdates   int        `json:"pendingUpdates"`
	LastErrorAt      *time.Time `json:"lastErrorAt,omitempty"`
	LastErrorMessage string     `json:"lastErrorMessage,omitempty"`
}

type WebhookInspector interface {
	WebhookInfo(ctx context.Context, expectedURL string) (WebhookStatus, error)
}

type ImportStatsStore interface {
	ImportStats(ctx context.Context, provider string, now time.Time) (store.ImportStats, error)
}

// Thresholds above which the health check warns.
const (
	warnPendingUpdates = 100
	warnRecentError    = 15 * time.Minute
	warnOldestWaiting  = 15 * time.Minute
	warnFailedLastHour = 10
)

// Watched is one running bot, as the Monitor sees it.
type Watched struct {
	Name       string
	Webhook    WebhookInspector
	WebhookURL string
	Metrics    *Metrics
}

// Monitor reports each bot's webhook, import queue and counters, for the
// ops endpoint and the periodic health log.
type Monitor struct {
	bots  []Watched
	stats ImportStatsStore
	now   func() time.Time
}

func NewMonitor(stats ImportStatsStore, bots ...Watched) *Monitor {
	return &Monitor{bots: bots, stats: stats, now: time.Now}
}

// BotHealth is one bot's state. Problems lists what needs attention.
type BotHealth struct {
	Provider     string            `json:"provider"`
	Webhook      *WebhookStatus    `json:"webhook,omitempty"`
	WebhookError string            `json:"webhookError,omitempty"`
	Imports      store.ImportStats `json:"imports"`
	Counters     MetricsSnapshot   `json:"counters"`
	Problems     []string          `json:"problems"`
}

func (m *Monitor) Health(ctx context.Context) ([]BotHealth, error) {
	now := m.now()
	report := make([]BotHealth, 0, len(m.bots))
	for _, b := range m.bots {
		h := BotHealth{Provider: b.Name, Counters: b.Metrics.Snapshot(), Problems: []string{}}
		stats, err := m.stats.ImportStats(ctx, b.Name, now)
		if err != nil {
			return nil, err
		}
		h.Imports = stats
		lookup, cancel := context.WithTimeout(ctx, 10*time.Second)
		status, err := b.Webhook.WebhookInfo(lookup, b.WebhookURL)
		cancel()
		if err != nil {
			h.WebhookError = err.Error()
			h.Problems = append(h.Problems, "provider API unreachable")
		} else {
			h.Webhook = &status
			switch {
			case !status.Registered:
				h.Problems = append(h.Problems, "webhook not registered")
			case !status.MatchesExpected:
				h.Problems = append(h.Problems, "webhook points somewhere else")
			}
			if status.PendingUpdates > warnPendingUpdates {
				h.Problems = append(h.Problems, "many updates waiting for delivery")
			}
			if status.LastErrorAt != nil && now.Sub(*status.LastErrorAt) < warnRecentError {
				h.Problems = append(h.Problems, "provider recently failed to deliver updates")
			}
		}
		if stats.OldestWaiting != nil && now.Sub(*stats.OldestWaiting) > warnOldestWaiting {
			h.Problems = append(h.Problems, "imports stuck in the queue")
		}
		if stats.FailedLastHour > warnFailedLastHour {
			h.Problems = append(h.Problems, "many failed imports in the last hour")
		}
		report = append(report, h)
	}
	return report, nil
}

// LogHealth logs every bot's health now and then until ctx ends, at warning
// level when something needs attention.
func (m *Monitor) LogHealth(ctx context.Context, every time.Duration) {
	ticker := time.NewTicker(every)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
		report, err := m.Health(ctx)
		if err != nil {
			slog.Error("bot health check failed", "error", err)
			continue
		}
		for _, h := range report {
			attrs := []any{
				"provider", h.Provider, "queued", h.Imports.Queued, "downloading", h.Imports.Downloading,
				"done_last_hour", h.Imports.DoneLastHour, "failed_last_hour", h.Imports.FailedLastHour,
				"updates", h.Counters.Updates, "imports_done", h.Counters.ImportsDone,
				"imports_failed", h.Counters.ImportsFailed, "sends_failed", h.Counters.SendsFailed,
			}
			if h.Webhook != nil {
				attrs = append(attrs, "pending_updates", h.Webhook.PendingUpdates)
			}
			if len(h.Problems) > 0 {
				slog.Warn("bot health", append(attrs, "problems", h.Problems, "webhook_error", h.WebhookError)...)
			} else {
				slog.Info("bot health", attrs...)
			}
		}
	}
}
