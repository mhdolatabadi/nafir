package store

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

var (
	// ErrEmailAlreadyVerified is returned when an account that already
	// proved its address asks for a code, confirms one or changes address
	// through the unverified-only path.
	ErrEmailAlreadyVerified = errors.New("email is already verified")
	// ErrNoEmailCode means there is no code outstanding, or it was sent to
	// an address the account no longer has.
	ErrNoEmailCode = errors.New("no email verification code")
	// ErrEmailCodeExpired means the outstanding code is too old.
	ErrEmailCodeExpired = errors.New("email verification code expired")
	// ErrEmailCodeLocked means the code had too many wrong attempts; a new
	// one has to be sent.
	ErrEmailCodeLocked = errors.New("too many wrong email verification codes")
	// ErrEmailCodeMismatch is a wrong code; the attempt was counted.
	ErrEmailCodeMismatch = errors.New("wrong email verification code")
)

// EmailCodeAttempt is the result of a wrong code: how many tries are left.
type EmailCodeAttempt struct {
	AttemptsLeft int
}

// SetEmailCode replaces the account's outstanding code with codeHash for
// email, valid until expiresAt, with no attempts used. It refuses accounts
// that already verified their address, and ErrNoEmailCode means the account's
// address is no longer email.
func (u *Users) SetEmailCode(ctx context.Context, userID, email, codeHash string, expiresAt time.Time) (User, error) {
	var user User
	err := pgx.BeginFunc(ctx, u.pool, func(tx pgx.Tx) error {
		err := scanUser(tx.QueryRow(ctx,
			`SELECT `+userColumns+` FROM users WHERE id::text = $1 FOR UPDATE`, userID,
		), &user)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if user.EmailVerifiedAt != nil {
			return ErrEmailAlreadyVerified
		}
		if user.Email != email {
			return ErrNoEmailCode
		}
		_, err = tx.Exec(ctx,
			`INSERT INTO email_verification_codes (user_id, email, code_hash, expires_at)
			 VALUES ($1::uuid, $2, $3, $4)
			 ON CONFLICT (user_id) DO UPDATE SET email = EXCLUDED.email,
			   code_hash = EXCLUDED.code_hash, expires_at = EXCLUDED.expires_at,
			   attempts = 0, created_at = now()`,
			user.ID, email, codeHash, expiresAt)
		return err
	})
	return user, err
}

// ConfirmEmail checks a code against the outstanding one with matches,
// which compares it to the hash stored for the address it was sent to. A wrong code uses up one of
// maxAttempts; once they are gone the code stops working. The right code
// marks the address verified and removes the code.
func (u *Users) ConfirmEmail(ctx context.Context, userID string, now time.Time, maxAttempts int, matches func(email, codeHash string) bool) (User, EmailCodeAttempt, error) {
	var user User
	tx, err := u.pool.Begin(ctx)
	if err != nil {
		return user, EmailCodeAttempt{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	err = scanUser(tx.QueryRow(ctx,
		`SELECT `+userColumns+` FROM users WHERE id::text = $1 FOR UPDATE`, userID,
	), &user)
	if errors.Is(err, pgx.ErrNoRows) {
		return user, EmailCodeAttempt{}, ErrNotFound
	}
	if err != nil {
		return user, EmailCodeAttempt{}, err
	}
	if user.EmailVerifiedAt != nil {
		return user, EmailCodeAttempt{}, ErrEmailAlreadyVerified
	}
	var email, codeHash string
	var expiresAt time.Time
	var attempts int
	err = tx.QueryRow(ctx,
		`SELECT email, code_hash, expires_at, attempts
		 FROM email_verification_codes WHERE user_id = $1::uuid`, user.ID,
	).Scan(&email, &codeHash, &expiresAt, &attempts)
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && email != user.Email) {
		return user, EmailCodeAttempt{}, ErrNoEmailCode
	}
	if err != nil {
		return user, EmailCodeAttempt{}, err
	}
	if !now.Before(expiresAt) {
		return user, EmailCodeAttempt{}, ErrEmailCodeExpired
	}
	if attempts >= maxAttempts {
		return user, EmailCodeAttempt{}, ErrEmailCodeLocked
	}
	if !matches(email, codeHash) {
		// The wrong attempt is committed even though it is reported as an
		// error, or guessing would cost nothing.
		attempts++
		if _, err := tx.Exec(ctx,
			`UPDATE email_verification_codes SET attempts = $2 WHERE user_id = $1::uuid`,
			user.ID, attempts); err != nil {
			return user, EmailCodeAttempt{}, err
		}
		if err := tx.Commit(ctx); err != nil {
			return user, EmailCodeAttempt{}, err
		}
		return user, EmailCodeAttempt{AttemptsLeft: maxAttempts - attempts}, ErrEmailCodeMismatch
	}
	if _, err := tx.Exec(ctx,
		`DELETE FROM email_verification_codes WHERE user_id = $1::uuid`, user.ID); err != nil {
		return user, EmailCodeAttempt{}, err
	}
	if err := scanUser(tx.QueryRow(ctx,
		`UPDATE users SET email_verified_at = $2 WHERE id = $1::uuid RETURNING `+userColumns,
		user.ID, now,
	), &user); err != nil {
		return user, EmailCodeAttempt{}, err
	}
	return user, EmailCodeAttempt{}, tx.Commit(ctx)
}

// ChangeUnverifiedEmail corrects the address of an account that has not
// verified it yet, and drops any code sent to the old one.
func (u *Users) ChangeUnverifiedEmail(ctx context.Context, userID, email string) (User, error) {
	var user User
	err := pgx.BeginFunc(ctx, u.pool, func(tx pgx.Tx) error {
		err := scanUser(tx.QueryRow(ctx,
			`SELECT `+userColumns+` FROM users WHERE id::text = $1 FOR UPDATE`, userID,
		), &user)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if user.EmailVerifiedAt != nil {
			return ErrEmailAlreadyVerified
		}
		if user.Email == email {
			return nil
		}
		err = scanUser(tx.QueryRow(ctx,
			`UPDATE users SET email = $2 WHERE id = $1::uuid RETURNING `+userColumns,
			user.ID, email,
		), &user)
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == uniqueViolation {
			return ErrEmailTaken
		}
		if err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `DELETE FROM email_verification_codes WHERE user_id = $1::uuid`, user.ID)
		return err
	})
	return user, err
}
