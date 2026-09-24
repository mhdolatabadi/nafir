package store

import (
	"context"
	"errors"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// newTestPool connects to TEST_DATABASE_URL, a disposable database the test may
// wipe. The tests are skipped when it is not set.
func newTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	if _, err := pool.Exec(ctx, "DROP TABLE IF EXISTS users, schema_migrations"); err != nil {
		t.Fatal(err)
	}
	if err := Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	return pool
}

func TestMigrateIsIdempotent(t *testing.T) {
	pool := newTestPool(t)
	if err := Migrate(context.Background(), pool); err != nil {
		t.Fatalf("second migration run failed: %v", err)
	}
}

func TestUsers(t *testing.T) {
	ctx := context.Background()
	users := NewUsers(newTestPool(t))

	created, err := users.Create(ctx, "a@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	if created.ID == "" || created.CreatedAt.IsZero() {
		t.Fatalf("incomplete user: %+v", created)
	}
	if _, err := users.Create(ctx, "a@example.com", "other"); !errors.Is(err, ErrEmailTaken) {
		t.Fatalf("expected ErrEmailTaken, got %v", err)
	}

	byEmail, hash, err := users.ByEmail(ctx, "a@example.com")
	if err != nil || byEmail.ID != created.ID || hash != "hash" {
		t.Fatalf("ByEmail = %+v, %q, %v", byEmail, hash, err)
	}
	if _, _, err := users.ByEmail(ctx, "b@example.com"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}

	byID, err := users.ByID(ctx, created.ID)
	if err != nil || byID.Email != "a@example.com" {
		t.Fatalf("ByID = %+v, %v", byID, err)
	}
	for _, id := range []string{"00000000-0000-0000-0000-000000000000", "not-a-uuid"} {
		if _, err := users.ByID(ctx, id); !errors.Is(err, ErrNotFound) {
			t.Fatalf("ByID(%q): expected ErrNotFound, got %v", id, err)
		}
	}
}
