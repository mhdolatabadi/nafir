package auth

import (
	"context"
	"errors"
	"testing"
	"time"
)

type fakeEpochs struct {
	epochs  map[string]int64
	lookups int
	err     error
}

func (f *fakeEpochs) lookup(_ context.Context, userID string) (int64, error) {
	f.lookups++
	if f.err != nil {
		return 0, f.err
	}
	epoch, ok := f.epochs[userID]
	if !ok {
		return 0, ErrNoAccount
	}
	return epoch, nil
}

func newSessionTokens(t *testing.T, epochs *fakeEpochs) (*Tokens, *Sessions, *time.Time) {
	t.Helper()
	tokens, err := NewTokens(testSecret, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	sessions := NewSessions(epochs.lookup, 30*time.Second, 100)
	sessions.now = func() time.Time { return now }
	return tokens.WithSessions(sessions), sessions, &now
}

func TestAuthorizeEndsOldEpochs(t *testing.T) {
	ctx := context.Background()
	epochs := &fakeEpochs{epochs: map[string]int64{"u1": 0}}
	tokens, sessions, _ := newSessionTokens(t, epochs)
	old, _, _ := tokens.Issue("u1")
	if id, err := tokens.Authorize(ctx, old); err != nil || id != "u1" {
		t.Fatalf("Authorize = %q, %v", id, err)
	}

	epochs.epochs["u1"] = 1
	sessions.Forget("u1")
	if _, err := tokens.Authorize(ctx, old); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("a token from a revoked epoch = %v", err)
	}
	current, _, _ := tokens.IssueSession("u1", 1)
	if _, err := tokens.Authorize(ctx, current); err != nil {
		t.Fatalf("a token in the current epoch = %v", err)
	}
	// Verify alone does not look at revocation.
	if _, err := tokens.Verify(old); err != nil {
		t.Fatalf("Verify = %v", err)
	}
}

func TestAuthorizeRejectsDeletedAccounts(t *testing.T) {
	ctx := context.Background()
	epochs := &fakeEpochs{epochs: map[string]int64{"u1": 0}}
	tokens, sessions, _ := newSessionTokens(t, epochs)
	token, _, _ := tokens.Issue("u1")
	delete(epochs.epochs, "u1")
	sessions.Forget("u1")
	if _, err := tokens.Authorize(ctx, token); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("a deleted account's token = %v", err)
	}
}

func TestSessionEpochsAreCachedBriefly(t *testing.T) {
	ctx := context.Background()
	epochs := &fakeEpochs{epochs: map[string]int64{"u1": 0}}
	tokens, _, now := newSessionTokens(t, epochs)
	token, _, _ := tokens.Issue("u1")
	for range 5 {
		if _, err := tokens.Authorize(ctx, token); err != nil {
			t.Fatal(err)
		}
	}
	if epochs.lookups != 1 {
		t.Fatalf("lookups = %d, want 1", epochs.lookups)
	}
	// Another process revoked: this one notices once the entry expires.
	epochs.epochs["u1"] = 1
	*now = now.Add(31 * time.Second)
	if _, err := tokens.Authorize(ctx, token); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("after the cache TTL = %v", err)
	}
}

func TestSessionLookupFailureIsNotAnInvalidToken(t *testing.T) {
	epochs := &fakeEpochs{err: errors.New("database down")}
	tokens, _, _ := newSessionTokens(t, epochs)
	token, _, _ := tokens.Issue("u1")
	_, err := tokens.Authorize(context.Background(), token)
	if err == nil || errors.Is(err, ErrInvalidToken) {
		t.Fatalf("a failed lookup = %v; it must not look like a bad token", err)
	}
}

func TestSessionCacheStaysBounded(t *testing.T) {
	epochs := &fakeEpochs{epochs: map[string]int64{}}
	sessions := NewSessions(epochs.lookup, time.Minute, 3)
	for _, id := range []string{"a", "b", "c", "d", "e"} {
		epochs.epochs[id] = 0
		if err := sessions.check(context.Background(), id, 0); err != nil {
			t.Fatal(err)
		}
	}
	if len(sessions.entries) > 3 {
		t.Fatalf("cache holds %d entries, limit 3", len(sessions.entries))
	}
}
