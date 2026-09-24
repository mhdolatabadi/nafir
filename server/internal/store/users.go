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
}

type Users struct {
	pool *pgxpool.Pool
}

func NewUsers(pool *pgxpool.Pool) *Users {
	return &Users{pool: pool}
}

func (u *Users) Create(ctx context.Context, email, passwordHash string) (User, error) {
	var user User
	err := u.pool.QueryRow(ctx,
		`INSERT INTO users (email, password_hash) VALUES ($1, $2)
		 RETURNING id::text, email, created_at`,
		email, passwordHash,
	).Scan(&user.ID, &user.Email, &user.CreatedAt)
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
	err := u.pool.QueryRow(ctx,
		`SELECT id::text, email, created_at, password_hash FROM users WHERE email = $1`, email,
	).Scan(&user.ID, &user.Email, &user.CreatedAt, &hash)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, "", ErrNotFound
	}
	return user, hash, err
}

func (u *Users) ByID(ctx context.Context, id string) (User, error) {
	var user User
	// Comparing as text avoids a cast error when a token carries a malformed ID.
	err := u.pool.QueryRow(ctx,
		`SELECT id::text, email, created_at FROM users WHERE id::text = $1`, id,
	).Scan(&user.ID, &user.Email, &user.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrNotFound
	}
	return user, err
}
