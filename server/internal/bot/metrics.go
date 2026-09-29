package bot

import "sync/atomic"

// Metrics counts what one provider's bot has done since the API started.
type Metrics struct {
	Updates       atomic.Int64
	Duplicates    atomic.Int64
	Links         atomic.Int64
	LinkFailures  atomic.Int64
	ImportsDone   atomic.Int64
	ImportsFailed atomic.Int64
	SendsDone     atomic.Int64
	SendsFailed   atomic.Int64
	ReplyFailures atomic.Int64
}

// MetricsSnapshot is Metrics at one moment, ready to encode.
type MetricsSnapshot struct {
	Updates       int64 `json:"updates"`
	Duplicates    int64 `json:"duplicates"`
	Links         int64 `json:"links"`
	LinkFailures  int64 `json:"linkFailures"`
	ImportsDone   int64 `json:"importsDone"`
	ImportsFailed int64 `json:"importsFailed"`
	SendsDone     int64 `json:"sendsDone"`
	SendsFailed   int64 `json:"sendsFailed"`
	ReplyFailures int64 `json:"replyFailures"`
}

func (m *Metrics) Snapshot() MetricsSnapshot {
	return MetricsSnapshot{
		Updates: m.Updates.Load(), Duplicates: m.Duplicates.Load(),
		Links: m.Links.Load(), LinkFailures: m.LinkFailures.Load(),
		ImportsDone: m.ImportsDone.Load(), ImportsFailed: m.ImportsFailed.Load(),
		SendsDone: m.SendsDone.Load(), SendsFailed: m.SendsFailed.Load(),
		ReplyFailures: m.ReplyFailures.Load(),
	}
}
