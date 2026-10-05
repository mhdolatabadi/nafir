package store

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
)

// ListAccounts returns a bounded page in stable order. Search is literal,
// including percent and underscore characters.
func (u *Users) ListAccounts(ctx context.Context, query string, offset, limit int) ([]User, bool, error) {
	rows, err := u.pool.Query(ctx,
		`SELECT id::text, email, created_at, verified, verified_at
		 FROM users WHERE strpos(lower(email), lower($1)) > 0
		 ORDER BY created_at DESC, id DESC LIMIT $2 OFFSET $3`,
		query, limit+1, offset)
	if err != nil {
		return nil, false, err
	}
	defer rows.Close()
	users := make([]User, 0)
	for rows.Next() {
		var user User
		if err := rows.Scan(&user.ID, &user.Email, &user.CreatedAt, &user.Verified, &user.VerifiedAt); err != nil {
			return nil, false, err
		}
		users = append(users, user)
	}
	if err := rows.Err(); err != nil {
		return nil, false, err
	}
	more := len(users) > limit
	if more {
		users = users[:limit]
	}
	return users, more, nil
}

// SetVerification records a real change and its actor in one transaction.
func (u *Users) SetVerification(ctx context.Context, id, actorID string, verified bool) (User, error) {
	var user User
	err := pgx.BeginFunc(ctx, u.pool, func(tx pgx.Tx) error {
		err := tx.QueryRow(ctx,
			`SELECT id::text, email, created_at, verified, verified_at
			 FROM users WHERE id::text = $1 FOR UPDATE`, id,
		).Scan(&user.ID, &user.Email, &user.CreatedAt, &user.Verified, &user.VerifiedAt)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil || user.Verified == verified {
			return err
		}
		err = tx.QueryRow(ctx,
			`UPDATE users SET verified = $2,
			 verified_at = CASE WHEN $2 THEN now() ELSE NULL END,
			 verified_by = CASE WHEN $2 THEN $3::uuid ELSE NULL END
			 WHERE id::text = $1
			 RETURNING id::text, email, created_at, verified, verified_at`,
			id, verified, actorID,
		).Scan(&user.ID, &user.Email, &user.CreatedAt, &user.Verified, &user.VerifiedAt)
		if err != nil {
			return err
		}
		_, err = tx.Exec(ctx,
			`INSERT INTO account_verification_audit (account_id, actor_id, verified)
			 VALUES ($1::uuid, $2::uuid, $3)`, id, actorID, verified)
		return err
	})
	return user, err
}
