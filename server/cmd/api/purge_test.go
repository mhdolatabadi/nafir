package main

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/store"
)

type fakePurgeQueue struct {
	pending []store.AccountDeletion
	now     time.Time
	marked  []string
}

func (q *fakePurgeQueue) PendingAccountPurges(context.Context, int) ([]store.AccountDeletion, error) {
	return q.pending, nil
}

func (q *fakePurgeQueue) MarkAccountPurged(_ context.Context, userID string) (bool, error) {
	for _, d := range q.pending {
		if d.UserID == userID && !q.now.Before(d.PurgeAfter) {
			q.marked = append(q.marked, userID)
			return true, nil
		}
	}
	return false, nil
}

type fakePrefixRemover struct {
	removed []string
	fail    map[string]bool
}

func (r *fakePrefixRemover) RemovePrefix(_ context.Context, prefix string) (int, error) {
	if r.fail[prefix] {
		return 0, errors.New("storage down")
	}
	r.removed = append(r.removed, prefix)
	return 1, nil
}

func TestPurgeAccountsOnce(t *testing.T) {
	now := time.Now()
	queue := &fakePurgeQueue{now: now, pending: []store.AccountDeletion{
		{UserID: "expired", ObjectPrefix: "users/expired/", PurgeAfter: now.Add(-time.Minute)},
		{UserID: "recent", ObjectPrefix: "users/recent/", PurgeAfter: now.Add(time.Hour)},
		{UserID: "failing", ObjectPrefix: "users/failing/", PurgeAfter: now.Add(-time.Minute)},
	}}
	objects := &fakePrefixRemover{fail: map[string]bool{"users/failing/": true}}

	purgeAccountsOnce(context.Background(), queue, objects, 10)

	// Every account is swept, a recent one again later, and one whose
	// storage failed is retried instead of being marked purged.
	if len(objects.removed) != 2 || objects.removed[0] != "users/expired/" || objects.removed[1] != "users/recent/" {
		t.Fatalf("removed = %v", objects.removed)
	}
	if len(queue.marked) != 1 || queue.marked[0] != "expired" {
		t.Fatalf("marked = %v", queue.marked)
	}
}
