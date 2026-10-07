package store

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestExistingAccountsCountAsEmailVerified(t *testing.T) {
	ctx := context.Background()
	pool := newTestPool(t)
	// Roll the migration back to before 016 with an account in place, then
	// apply it again, as an upgrade does.
	if _, err := pool.Exec(ctx, `DROP TABLE email_verification_codes;
		ALTER TABLE users DROP COLUMN email_verified_at;
		DELETE FROM schema_migrations WHERE version >= 'migrations/016';
		INSERT INTO users (email, password_hash) VALUES ('old@example.com', 'hash')`); err != nil {
		t.Fatal(err)
	}
	if err := Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	users := NewUsers(pool)
	old, _, err := users.ByEmail(ctx, "old@example.com")
	if err != nil || old.EmailVerifiedAt == nil {
		t.Fatalf("existing account = %+v, %v; want verified", old, err)
	}
	fresh, err := users.Create(ctx, "new@example.com", "hash")
	if err != nil || fresh.EmailVerifiedAt != nil {
		t.Fatalf("new account = %+v, %v; want unverified", fresh, err)
	}
}

func TestEmailCodeLifecycle(t *testing.T) {
	ctx := context.Background()
	users := NewUsers(newTestPool(t))
	user, err := users.Create(ctx, "a@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	is := func(want string) func(string, string) bool {
		return func(email, hash string) bool { return email == "a@example.com" && hash == want }
	}

	if _, _, err := users.ConfirmEmail(ctx, user.ID, now, 5, is("h1")); !errors.Is(err, ErrNoEmailCode) {
		t.Fatalf("confirm without a code = %v", err)
	}
	if _, err := users.SetEmailCode(ctx, user.ID, "a@example.com", "h1", now.Add(15*time.Minute)); err != nil {
		t.Fatal(err)
	}
	// Wrong attempts are counted, and survive across calls.
	for left := 4; left >= 0; left-- {
		_, attempt, err := users.ConfirmEmail(ctx, user.ID, now, 5, is("other"))
		if !errors.Is(err, ErrEmailCodeMismatch) || attempt.AttemptsLeft != left {
			t.Fatalf("wrong code = %+v, %v; want %d left", attempt, err, left)
		}
	}
	// After five, even the right code no longer works.
	if _, _, err := users.ConfirmEmail(ctx, user.ID, now, 5, is("h1")); !errors.Is(err, ErrEmailCodeLocked) {
		t.Fatalf("sixth attempt = %v; want locked", err)
	}

	// A new code starts over; an expired one never works.
	if _, err := users.SetEmailCode(ctx, user.ID, "a@example.com", "h2", now.Add(15*time.Minute)); err != nil {
		t.Fatal(err)
	}
	if _, _, err := users.ConfirmEmail(ctx, user.ID, now.Add(15*time.Minute), 5, is("h2")); !errors.Is(err, ErrEmailCodeExpired) {
		t.Fatalf("expired code = %v", err)
	}
	verified, _, err := users.ConfirmEmail(ctx, user.ID, now.Add(14*time.Minute), 5, is("h2"))
	if err != nil || verified.EmailVerifiedAt == nil {
		t.Fatalf("right code = %+v, %v", verified, err)
	}
	if verified.Verified {
		t.Fatal("email verification set the admin's verification badge")
	}
	if _, err := users.SetEmailCode(ctx, user.ID, "a@example.com", "h3", now.Add(time.Minute)); !errors.Is(err, ErrEmailAlreadyVerified) {
		t.Fatalf("code for a verified account = %v", err)
	}
	if _, err := users.ChangeUnverifiedEmail(ctx, user.ID, "b@example.com"); !errors.Is(err, ErrEmailAlreadyVerified) {
		t.Fatalf("changing a verified address = %v", err)
	}
}

func TestChangingUnverifiedEmailDropsTheCode(t *testing.T) {
	ctx := context.Background()
	users := NewUsers(newTestPool(t))
	user, _ := users.Create(ctx, "typo@exmaple.com", "hash")
	if _, err := users.Create(ctx, "taken@example.com", "hash"); err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	if _, err := users.SetEmailCode(ctx, user.ID, "typo@exmaple.com", "h1", now.Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	if _, err := users.ChangeUnverifiedEmail(ctx, user.ID, "taken@example.com"); !errors.Is(err, ErrEmailTaken) {
		t.Fatalf("change to a taken address = %v", err)
	}
	changed, err := users.ChangeUnverifiedEmail(ctx, user.ID, "right@example.com")
	if err != nil || changed.Email != "right@example.com" || changed.EmailVerifiedAt != nil {
		t.Fatalf("change = %+v, %v", changed, err)
	}
	anything := func(string, string) bool { return true }
	if _, _, err := users.ConfirmEmail(ctx, user.ID, now, 5, anything); !errors.Is(err, ErrNoEmailCode) {
		t.Fatalf("the old address's code still works: %v", err)
	}
	// A code drawn for the old address is refused rather than stored.
	if _, err := users.SetEmailCode(ctx, user.ID, "typo@exmaple.com", "h2", now.Add(time.Hour)); !errors.Is(err, ErrNoEmailCode) {
		t.Fatalf("code for a stale address = %v", err)
	}
}
