package bot

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/store"
)

type fakeInspector struct {
	status WebhookStatus
	err    error
}

func (f fakeInspector) WebhookInfo(context.Context, string) (WebhookStatus, error) {
	return f.status, f.err
}

type fakeStats store.ImportStats

func (f fakeStats) ImportStats(context.Context, string, time.Time) (store.ImportStats, error) {
	return store.ImportStats(f), nil
}

func TestMonitorFlagsWhatNeedsAttention(t *testing.T) {
	now := time.Date(2026, 9, 29, 12, 0, 0, 0, time.UTC)
	recent := now.Add(-time.Minute)
	stuck := now.Add(-time.Hour)
	metrics := &Metrics{}
	metrics.ImportsDone.Add(3)

	cases := []struct {
		name    string
		webhook fakeInspector
		stats   fakeStats
		want    []string
	}{
		{"healthy", fakeInspector{status: WebhookStatus{Registered: true, MatchesExpected: true}}, fakeStats{}, nil},
		{"unreachable", fakeInspector{err: errors.New("dial tcp: i/o timeout")}, fakeStats{}, []string{"provider API unreachable"}},
		{"not registered", fakeInspector{status: WebhookStatus{}}, fakeStats{}, []string{"webhook not registered"}},
		{"elsewhere", fakeInspector{status: WebhookStatus{Registered: true}}, fakeStats{}, []string{"webhook points somewhere else"}},
		{"backlog and errors", fakeInspector{status: WebhookStatus{
			Registered: true, MatchesExpected: true, PendingUpdates: 500, LastErrorAt: &recent,
		}}, fakeStats{}, []string{"many updates waiting for delivery", "provider recently failed to deliver updates"}},
		{"stuck queue", fakeInspector{status: WebhookStatus{Registered: true, MatchesExpected: true}},
			fakeStats{Queued: 2, OldestWaiting: &stuck, FailedLastHour: 11},
			[]string{"imports stuck in the queue", "many failed imports in the last hour"}},
	}
	for _, c := range cases {
		monitor := NewMonitor(c.stats, Watched{Name: "bale", Webhook: c.webhook, Metrics: metrics})
		monitor.now = func() time.Time { return now }
		report, err := monitor.Health(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		got := report[0].Problems
		if len(got) != len(c.want) {
			t.Errorf("%s: problems = %q, want %q", c.name, got, c.want)
			continue
		}
		for i := range got {
			if got[i] != c.want[i] {
				t.Errorf("%s: problems = %q, want %q", c.name, got, c.want)
			}
		}
		if report[0].Counters.ImportsDone != 3 {
			t.Errorf("%s: counters = %+v", c.name, report[0].Counters)
		}
	}
}
