package auth

import (
	"context"
	"errors"
	"sync"
	"time"
)

// ErrNoAccount is what a SessionLookup returns for an account that does not
// exist (any more); its tokens are then invalid.
var ErrNoAccount = errors.New("account does not exist")

// SessionLookup returns the account's current session epoch.
type SessionLookup func(ctx context.Context, userID string) (int64, error)

// Sessions checks tokens against each account's current session epoch. The
// epoch is cached for a short time so most requests skip the database; this
// process forgets an account's entry as soon as it revokes or deletes it, so
// the TTL only bounds how long another process could lag behind.
type Sessions struct {
	lookup     SessionLookup
	ttl        time.Duration
	maxEntries int
	now        func() time.Time

	mu      sync.Mutex
	entries map[string]sessionEntry
}

type sessionEntry struct {
	epoch   int64
	missing bool
	expires time.Time
}

func NewSessions(lookup SessionLookup, ttl time.Duration, maxEntries int) *Sessions {
	return &Sessions{
		lookup: lookup, ttl: ttl, maxEntries: maxEntries, now: time.Now,
		entries: make(map[string]sessionEntry),
	}
}

// Forget drops the cached epoch, so the next request reads it afresh. Call it
// after revoking an account's sessions or deleting the account.
func (s *Sessions) Forget(userID string) {
	s.mu.Lock()
	delete(s.entries, userID)
	s.mu.Unlock()
}

func (s *Sessions) check(ctx context.Context, userID string, epoch int64) error {
	now := s.now()
	s.mu.Lock()
	entry, ok := s.entries[userID]
	s.mu.Unlock()
	if !ok || !now.Before(entry.expires) {
		current, err := s.lookup(ctx, userID)
		switch {
		case errors.Is(err, ErrNoAccount):
			entry = sessionEntry{missing: true}
		case err != nil:
			return err
		default:
			entry = sessionEntry{epoch: current}
		}
		entry.expires = now.Add(s.ttl)
		s.mu.Lock()
		if len(s.entries) >= s.maxEntries {
			clear(s.entries)
		}
		s.entries[userID] = entry
		s.mu.Unlock()
	}
	if entry.missing || entry.epoch != epoch {
		return ErrInvalidToken
	}
	return nil
}
