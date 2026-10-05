package store

import (
	"context"
	"errors"
	"testing"
)

func TestAccountVerificationPersistence(t *testing.T) {
	ctx := context.Background()
	pool := newTestPool(t)
	users := NewUsers(pool)
	admin, err := users.Create(ctx, "admin@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	target, err := users.Create(ctx, "literal_%@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	verified, err := users.SetVerification(ctx, target.ID, admin.ID, true)
	if err != nil || !verified.Verified || verified.VerifiedAt == nil {
		t.Fatalf("verify = %+v, %v", verified, err)
	}
	read, err := users.ByID(ctx, target.ID)
	if err != nil || !read.Verified {
		t.Fatalf("verification was not persisted: %+v, %v", read, err)
	}
	if _, err := users.SetVerification(ctx, target.ID, admin.ID, true); err != nil {
		t.Fatal(err)
	}
	var changes int
	if err := pool.QueryRow(ctx, "SELECT count(*) FROM account_verification_audit WHERE account_id::text = $1 AND actor_id::text = $2", target.ID, admin.ID).Scan(&changes); err != nil || changes != 1 {
		t.Fatalf("audit changes = %d, %v", changes, err)
	}
	if _, err := pool.Exec(ctx, "ALTER TABLE account_verification_audit ADD CONSTRAINT reject_revoke CHECK (verified)"); err != nil {
		t.Fatal(err)
	}
	if _, err := users.SetVerification(ctx, target.ID, admin.ID, false); err == nil {
		t.Fatal("expected audit failure")
	}
	read, _ = users.ByID(ctx, target.ID)
	if !read.Verified {
		t.Fatal("audit failure must roll back verification")
	}
	if _, err := pool.Exec(ctx, "ALTER TABLE account_verification_audit DROP CONSTRAINT reject_revoke"); err != nil {
		t.Fatal(err)
	}
	revoked, err := users.SetVerification(ctx, target.ID, admin.ID, false)
	if err != nil || revoked.Verified || revoked.VerifiedAt != nil {
		t.Fatalf("revoke = %+v, %v", revoked, err)
	}
	if _, err := users.SetVerification(ctx, "missing", admin.ID, true); !errors.Is(err, ErrNotFound) {
		t.Fatalf("missing account = %v", err)
	}
	page, more, err := users.ListAccounts(ctx, "_%", 0, 50)
	if err != nil || more || len(page) != 1 || page[0].ID != target.ID {
		t.Fatalf("literal search = %+v, %t, %v", page, more, err)
	}
	page, more, err = users.ListAccounts(ctx, "", 0, 1)
	if err != nil || !more || len(page) != 1 {
		t.Fatalf("first page = %+v, %t, %v", page, more, err)
	}
	next, more, err := users.ListAccounts(ctx, "", 1, 1)
	if err != nil || more || len(next) != 1 || next[0].ID == page[0].ID {
		t.Fatalf("next page = %+v, %t, %v", next, more, err)
	}
}
