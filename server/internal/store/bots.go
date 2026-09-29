package store

import (
	"context"
	"crypto/subtle"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type ChatState string

const (
	ChatIdle          ChatState = "idle"
	ChatAwaitingEmail ChatState = "awaiting_email"
	ChatAwaitingCode  ChatState = "awaiting_code"
)

var (
	ErrCodeInvalid     = errors.New("login code is wrong or expired")
	ErrCodeAttempts    = errors.New("too many wrong login codes")
	ErrDuplicateImport = errors.New("message was already imported")
)

// BotChat is one private chat with a bot. UserID is set while it is signed in.
type BotChat struct {
	Provider   string
	ChatID     string
	State      ChatState
	UserID     *string
	SignedInAt *time.Time
}

// LoginCode is a new email one-time code. UserID is nil when the email has no
// account; such a code is stored so the chat cannot tell, but never verifies.
type LoginCode struct {
	Provider  string
	ChatID    string
	Email     string
	UserID    *string
	CodeHash  []byte
	ExpiresAt time.Time
}

// Bots stores messenger chats, their login codes, processed updates and
// audio imports.
type Bots struct {
	pool *pgxpool.Pool
}

func NewBots(pool *pgxpool.Pool) *Bots {
	return &Bots{pool: pool}
}

// Chat returns the chat, or an idle signed-out chat if it has never been seen.
func (b *Bots) Chat(ctx context.Context, provider, chatID string) (BotChat, error) {
	chat := BotChat{Provider: provider, ChatID: chatID, State: ChatIdle}
	err := b.pool.QueryRow(ctx, `
		SELECT state, user_id::text, signed_in_at FROM bot_chats
		WHERE provider = $1 AND chat_id = $2
	`, provider, chatID).Scan(&chat.State, &chat.UserID, &chat.SignedInAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return chat, nil
	}
	return chat, err
}

// SetState changes what the chat's next plain message is taken as.
func (b *Bots) SetState(ctx context.Context, provider, chatID string, state ChatState) error {
	_, err := b.pool.Exec(ctx, `
		INSERT INTO bot_chats (provider, chat_id, state) VALUES ($1, $2, $3)
		ON CONFLICT (provider, chat_id) DO UPDATE SET state = $3, updated_at = now()
	`, provider, chatID, string(state))
	return err
}

// SignOut unbinds the chat from its account and forgets unused codes.
func (b *Bots) SignOut(ctx context.Context, provider, chatID string) error {
	return pgx.BeginFunc(ctx, b.pool, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `
			UPDATE bot_chats SET user_id = NULL, signed_in_at = NULL, state = 'idle', updated_at = now()
			WHERE provider = $1 AND chat_id = $2
		`, provider, chatID); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `
			DELETE FROM bot_login_codes WHERE provider = $1 AND chat_id = $2 AND used_at IS NULL
		`, provider, chatID)
		return err
	})
}

// CodesSince counts codes issued to the chat and to the email since a time,
// and when the chat's latest code was issued.
func (b *Bots) CodesSince(ctx context.Context, provider, chatID, email string, since time.Time) (forChat, forEmail int, last *time.Time, err error) {
	err = b.pool.QueryRow(ctx, `
		SELECT
			COUNT(*) FILTER (WHERE provider = $1 AND chat_id = $2 AND created_at >= $4)::integer,
			COUNT(*) FILTER (WHERE email = $3 AND created_at >= $4)::integer,
			MAX(created_at) FILTER (WHERE provider = $1 AND chat_id = $2)
		FROM bot_login_codes
		WHERE (provider = $1 AND chat_id = $2) OR email = $3
	`, provider, chatID, email, since).Scan(&forChat, &forEmail, &last)
	return forChat, forEmail, last, err
}

// AddCode replaces the chat's unused codes with a new one and waits for it.
func (b *Bots) AddCode(ctx context.Context, code LoginCode) error {
	return pgx.BeginFunc(ctx, b.pool, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `
			UPDATE bot_login_codes SET expires_at = LEAST(expires_at, now())
			WHERE provider = $1 AND chat_id = $2 AND used_at IS NULL
		`, code.Provider, code.ChatID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO bot_login_codes (provider, chat_id, email, user_id, code_hash, expires_at)
			VALUES ($1, $2, $3, $4::uuid, $5, $6)
		`, code.Provider, code.ChatID, code.Email, code.UserID, code.CodeHash, code.ExpiresAt); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `
			INSERT INTO bot_chats (provider, chat_id, state) VALUES ($1, $2, 'awaiting_code')
			ON CONFLICT (provider, chat_id) DO UPDATE SET state = 'awaiting_code', updated_at = now()
		`, code.Provider, code.ChatID)
		return err
	})
}

// VerifyCode checks hash against the chat's current code. A match signs the
// chat in to the code's account and uses the code up; a miss counts as an
// attempt, and after maxAttempts the code is dead.
func (b *Bots) VerifyCode(ctx context.Context, provider, chatID string, hash []byte, now time.Time, maxAttempts int) (string, error) {
	var userID string
	var result error
	err := pgx.BeginFunc(ctx, b.pool, func(tx pgx.Tx) error {
		var id string
		var stored []byte
		var owner *string
		var attempts int
		err := tx.QueryRow(ctx, `
			SELECT id::text, code_hash, user_id::text, attempts FROM bot_login_codes
			WHERE provider = $1 AND chat_id = $2 AND used_at IS NULL AND expires_at > $3
			ORDER BY created_at DESC LIMIT 1
			FOR UPDATE
		`, provider, chatID, now).Scan(&id, &stored, &owner, &attempts)
		if errors.Is(err, pgx.ErrNoRows) {
			result = ErrCodeInvalid
			return nil
		}
		if err != nil {
			return err
		}
		if attempts >= maxAttempts {
			result = ErrCodeAttempts
			return nil
		}
		if subtle.ConstantTimeCompare(stored, hash) != 1 || owner == nil {
			if _, err := tx.Exec(ctx,
				`UPDATE bot_login_codes SET attempts = attempts + 1 WHERE id::text = $1`, id,
			); err != nil {
				return err
			}
			result = ErrCodeInvalid
			if attempts+1 >= maxAttempts {
				result = ErrCodeAttempts
			}
			return nil
		}
		if _, err := tx.Exec(ctx,
			`UPDATE bot_login_codes SET used_at = $2 WHERE id::text = $1`, id, now,
		); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO bot_chats (provider, chat_id, state, user_id, signed_in_at)
			VALUES ($1, $2, 'idle', $3::uuid, $4)
			ON CONFLICT (provider, chat_id) DO UPDATE
			SET state = 'idle', user_id = $3::uuid, signed_in_at = $4, updated_at = now()
		`, provider, chatID, *owner, now); err != nil {
			return err
		}
		userID = *owner
		return nil
	})
	if err != nil {
		return "", err
	}
	return userID, result
}

// FirstDelivery records an update and reports whether it is new.
func (b *Bots) FirstDelivery(ctx context.Context, provider, updateID string) (bool, error) {
	tag, err := b.pool.Exec(ctx, `
		INSERT INTO bot_updates (provider, update_id) VALUES ($1, $2)
		ON CONFLICT DO NOTHING
	`, provider, updateID)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() == 1, nil
}

// ForgetUpdatesBefore bounds the dedup table; providers stop redelivering
// long before this.
func (b *Bots) ForgetUpdatesBefore(ctx context.Context, before time.Time) error {
	_, err := b.pool.Exec(ctx, `DELETE FROM bot_updates WHERE received_at < $1`, before)
	return err
}

type ImportState string

const (
	ImportQueued      ImportState = "queued"
	ImportDownloading ImportState = "downloading"
	ImportDone        ImportState = "done"
	ImportFailed      ImportState = "failed"
)

type BotImport struct {
	ID        string
	Provider  string
	ChatID    string
	MessageID string
	UserID    string
	FileID    string
	FileName  string
	Title     *string
	Artist    *string
	SizeBytes int64
	State     ImportState
	TrackID   *string
	Error     *string
	Attempts  int
}

const importColumns = `id::text, provider, chat_id, message_id, user_id::text, file_id, file_name,
	title, artist, size_bytes, state, track_id::text, error, attempts`

func scanImport(row pgx.Row) (BotImport, error) {
	var i BotImport
	err := row.Scan(&i.ID, &i.Provider, &i.ChatID, &i.MessageID, &i.UserID, &i.FileID, &i.FileName,
		&i.Title, &i.Artist, &i.SizeBytes, &i.State, &i.TrackID, &i.Error, &i.Attempts)
	return i, err
}

// AddImport queues an import. The same message is queued only once, however
// often the provider redelivers it: ErrDuplicateImport.
func (b *Bots) AddImport(ctx context.Context, i BotImport) (BotImport, error) {
	created, err := scanImport(b.pool.QueryRow(ctx, `
		INSERT INTO bot_imports (provider, chat_id, message_id, user_id, file_id, file_name, title, artist, size_bytes)
		VALUES ($1, $2, $3, $4::uuid, $5, $6, $7, $8, $9)
		ON CONFLICT (provider, chat_id, message_id) DO NOTHING
		RETURNING `+importColumns,
		i.Provider, i.ChatID, i.MessageID, i.UserID, i.FileID, i.FileName, i.Title, i.Artist, i.SizeBytes))
	if errors.Is(err, pgx.ErrNoRows) {
		return BotImport{}, ErrDuplicateImport
	}
	return created, err
}

// StartImport claims a queued (or interrupted) import and counts the attempt.
// It returns false when another worker has it or it is finished.
func (b *Bots) StartImport(ctx context.Context, id string, staleBefore time.Time) (BotImport, bool, error) {
	claimed, err := scanImport(b.pool.QueryRow(ctx, `
		UPDATE bot_imports SET state = 'downloading', attempts = attempts + 1, updated_at = now()
		WHERE id::text = $1
		  AND (state = 'queued' OR (state = 'downloading' AND updated_at < $2))
		RETURNING `+importColumns, id, staleBefore))
	if errors.Is(err, pgx.ErrNoRows) {
		return BotImport{}, false, nil
	}
	return claimed, err == nil, err
}

// FinishImport records the outcome. trackID is set on success, reason on failure.
func (b *Bots) FinishImport(ctx context.Context, id string, trackID, reason *string) error {
	state := ImportDone
	if trackID == nil {
		state = ImportFailed
	}
	_, err := b.pool.Exec(ctx, `
		UPDATE bot_imports SET state = $2, track_id = $3::uuid, error = $4, updated_at = now()
		WHERE id::text = $1
	`, id, string(state), trackID, reason)
	return err
}

// RequeueImport puts an import that failed for a passing reason back in line.
func (b *Bots) RequeueImport(ctx context.Context, id string) error {
	_, err := b.pool.Exec(ctx,
		`UPDATE bot_imports SET state = 'queued', updated_at = now() WHERE id::text = $1`, id)
	return err
}

// UnfinishedImports lists imports interrupted by a restart, oldest first.
func (b *Bots) UnfinishedImports(ctx context.Context, limit int) ([]BotImport, error) {
	rows, err := b.pool.Query(ctx, `
		SELECT `+importColumns+` FROM bot_imports
		WHERE state IN ('queued', 'downloading')
		ORDER BY created_at, id LIMIT $1
	`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var imports []BotImport
	for rows.Next() {
		i, err := scanImport(rows)
		if err != nil {
			return nil, err
		}
		imports = append(imports, i)
	}
	return imports, rows.Err()
}
