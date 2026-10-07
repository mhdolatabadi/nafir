package store

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrEmailTaken = errors.New("email is already registered")
	ErrNotFound   = errors.New("not found")
)

const uniqueViolation = "23505"

type User struct {
	ID        string
	Email     string
	CreatedAt time.Time
	// Verified is the admin's manual verification badge (#172).
	Verified   bool
	VerifiedAt *time.Time
	// EmailVerifiedAt is when the owner proved they read this address; nil
	// until then. It is independent of Verified.
	EmailVerifiedAt *time.Time
}

// userColumns are the columns scanUser reads, in order.
const userColumns = `id::text, email, created_at, verified, verified_at, email_verified_at`

// scanUser reads userColumns, then any extra columns into extra.
func scanUser(row pgx.Row, user *User, extra ...any) error {
	return row.Scan(append([]any{
		&user.ID, &user.Email, &user.CreatedAt, &user.Verified, &user.VerifiedAt, &user.EmailVerifiedAt,
	}, extra...)...)
}

type Users struct {
	pool *pgxpool.Pool
}

func NewUsers(pool *pgxpool.Pool) *Users {
	return &Users{pool: pool}
}

func (u *Users) Create(ctx context.Context, email, passwordHash string) (User, error) {
	var user User
	err := scanUser(u.pool.QueryRow(ctx,
		`INSERT INTO users (email, password_hash) VALUES ($1, $2)
		 RETURNING `+userColumns,
		email, passwordHash,
	), &user)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == uniqueViolation {
		return User{}, ErrEmailTaken
	}
	return user, err
}

// ByEmail returns the user and their password hash.
func (u *Users) ByEmail(ctx context.Context, email string) (User, string, error) {
	var user User
	var hash string
	err := scanUser(u.pool.QueryRow(ctx,
		`SELECT `+userColumns+`, password_hash FROM users WHERE email = $1`, email,
	), &user, &hash)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, "", ErrNotFound
	}
	return user, hash, err
}

func (u *Users) ByID(ctx context.Context, id string) (User, error) {
	var user User
	// Comparing as text avoids a cast error when a token carries a malformed ID.
	err := scanUser(u.pool.QueryRow(ctx,
		`SELECT `+userColumns+` FROM users WHERE id::text = $1`, id,
	), &user)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrNotFound
	}
	return user, err
}
