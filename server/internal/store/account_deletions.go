package store

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// AccountDeletion is a deleted account whose objects under ObjectPrefix may
// still be in storage.
type AccountDeletion struct {
	UserID       string
	ObjectPrefix string
	DeletedAt    time.Time
	// PurgeAfter is when uploads that were in flight at deletion have
	// expired, so a prefix found empty from then on stays empty.
	PurgeAfter time.Time
}

// UserObjectPrefix is the storage prefix every object of the user lives under.
func UserObjectPrefix(userID string) string {
	return "users/" + userID + "/"
}

// Delete removes the user and, through the foreign-key cascades, their
// tracks, playlists with their tracks, members and likes, their memberships
// of other people's playlists, their likes, and their bot chats, link codes
// and imports. The same statement records the user's object prefix in
// account_deletions, so storage is cleaned up even if the process stops right
// after: objects are only ever removed once the account can't sign in.
// grace is how long uploads already handed out may still land in storage.
func (u *Users) Delete(ctx context.Context, userID string, grace time.Duration) (AccountDeletion, error) {
	var deletion AccountDeletion
	err := u.pool.QueryRow(ctx, `
		WITH gone AS (DELETE FROM users WHERE id::text = $1 RETURNING id)
		INSERT INTO account_deletions (user_id, object_prefix, purge_after)
		SELECT id, 'users/' || id::text || '/', now() + $2::bigint * interval '1 microsecond'
		FROM gone
		RETURNING user_id::text, object_prefix, deleted_at, purge_after
	`, userID, grace.Microseconds()).Scan(
		&deletion.UserID, &deletion.ObjectPrefix, &deletion.DeletedAt, &deletion.PurgeAfter)
	if errors.Is(err, pgx.ErrNoRows) {
		return AccountDeletion{}, ErrNotFound
	}
	return deletion, err
}

// PendingAccountPurges returns up to limit deleted accounts whose storage
// hasn't been confirmed empty yet, oldest first.
func (u *Users) PendingAccountPurges(ctx context.Context, limit int) ([]AccountDeletion, error) {
	rows, err := u.pool.Query(ctx, `
		SELECT user_id::text, object_prefix, deleted_at, purge_after
		FROM account_deletions
		WHERE purged_at IS NULL
		ORDER BY deleted_at, user_id
		LIMIT $1
	`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	pending := []AccountDeletion{}
	for rows.Next() {
		var d AccountDeletion
		if err := rows.Scan(&d.UserID, &d.ObjectPrefix, &d.DeletedAt, &d.PurgeAfter); err != nil {
			return nil, err
		}
		pending = append(pending, d)
	}
	return pending, rows.Err()
}

// MarkAccountPurged records that the deleted account's prefix was emptied.
// It reports false, and changes nothing, while uploads handed out before the
// deletion may still arrive, so the account is swept again later.
func (u *Users) MarkAccountPurged(ctx context.Context, userID string) (bool, error) {
	tag, err := u.pool.Exec(ctx, `
		UPDATE account_deletions SET purged_at = now()
		WHERE user_id::text = $1 AND purged_at IS NULL AND purge_after <= now()
	`, userID)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}
