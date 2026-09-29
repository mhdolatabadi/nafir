package bot

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"fmt"
	"math/big"
	"net/mail"
	"strings"
	"time"
	"unicode"

	"github.com/mhdolatabadi/nafir/server/internal/store"
)

var (
	ErrBadEmail  = errors.New("not an email address")
	ErrBadCode   = errors.New("login code is wrong or expired")
	ErrThrottled = errors.New("too many login codes requested")
)

// WaitError asks the chat to wait before requesting another code.
type WaitError struct{ Retry time.Duration }

func (e WaitError) Error() string {
	return fmt.Sprintf("wait %s before requesting another code", e.Retry)
}

type AuthStore interface {
	Chat(ctx context.Context, provider, chatID string) (store.BotChat, error)
	SignOut(ctx context.Context, provider, chatID string) error
	CodesSince(ctx context.Context, provider, chatID, email string, since time.Time) (int, int, *time.Time, error)
	AddCode(ctx context.Context, code store.LoginCode) error
	VerifyCode(ctx context.Context, provider, chatID string, hash []byte, now time.Time, maxAttempts int) (string, error)
}

type UserLookup interface {
	ByEmail(ctx context.Context, email string) (store.User, string, error)
	ByID(ctx context.Context, id string) (store.User, error)
}

type Mailer interface {
	Send(to, subject, body string) error
}

type AuthLimits struct {
	CodeTTL     time.Duration
	Cooldown    time.Duration
	PerHour     int
	MaxAttempts int
	SessionTTL  time.Duration
}

var DefaultAuthLimits = AuthLimits{
	CodeTTL: 10 * time.Minute, Cooldown: time.Minute, PerHour: 5,
	MaxAttempts: 5, SessionTTL: 180 * 24 * time.Hour,
}

// Auth signs chats in with one-time codes emailed to the account address.
// Passwords are never involved. Codes are stored as an HMAC bound to the
// chat, so a leaked table is useless and a code works only where requested.
type Auth struct {
	store  AuthStore
	users  UserLookup
	mailer Mailer
	key    []byte
	limits AuthLimits
	now    func() time.Time
}

func NewAuth(s AuthStore, users UserLookup, mailer Mailer, key []byte, limits AuthLimits) (*Auth, error) {
	if len(key) < 32 {
		return nil, errors.New("login code key must be at least 32 bytes")
	}
	return &Auth{store: s, users: users, mailer: mailer, key: key, limits: limits, now: time.Now}, nil
}

// RequestCode emails a code to the address if it has an account. The chat
// gets the same answer either way, so it cannot probe which emails exist.
func (a *Auth) RequestCode(ctx context.Context, provider, chatID, input string) error {
	email, ok := normalizeEmail(input)
	if !ok {
		return ErrBadEmail
	}
	now := a.now()
	forChat, forEmail, last, err := a.store.CodesSince(ctx, provider, chatID, email, now.Add(-time.Hour))
	if err != nil {
		return err
	}
	if last != nil && now.Sub(*last) < a.limits.Cooldown {
		return WaitError{Retry: a.limits.Cooldown - now.Sub(*last)}
	}
	if forChat >= a.limits.PerHour || forEmail >= a.limits.PerHour {
		return ErrThrottled
	}
	var userID *string
	user, _, err := a.users.ByEmail(ctx, email)
	switch {
	case err == nil:
		userID = &user.ID
	case !errors.Is(err, store.ErrNotFound):
		return err
	}
	code, err := newCode()
	if err != nil {
		return err
	}
	if err := a.store.AddCode(ctx, store.LoginCode{
		Provider: provider, ChatID: chatID, Email: email, UserID: userID,
		CodeHash: a.hash(provider, chatID, code), ExpiresAt: now.Add(a.limits.CodeTTL),
	}); err != nil {
		return err
	}
	if userID == nil {
		return nil
	}
	return a.mailer.Send(email, "کد ورود به نفیر", fmt.Sprintf(
		"کد ورود شما به ربات نفیر: %s\n\nاین کد تا %d دقیقه اعتبار دارد. اگر درخواستش نکرده‌اید، این ایمیل را نادیده بگیرید.",
		code, int(a.limits.CodeTTL.Minutes())))
}

// VerifyCode signs the chat in when the code matches.
func (a *Auth) VerifyCode(ctx context.Context, provider, chatID, input string) (string, error) {
	code, ok := normalizeCode(input)
	if !ok {
		return "", ErrBadCode
	}
	userID, err := a.store.VerifyCode(ctx, provider, chatID, a.hash(provider, chatID, code), a.now(), a.limits.MaxAttempts)
	if errors.Is(err, store.ErrCodeInvalid) || errors.Is(err, store.ErrCodeAttempts) {
		return "", ErrBadCode
	}
	return userID, err
}

// Session returns the chat's signed-in user, signing out expired sessions.
func (a *Auth) Session(ctx context.Context, provider, chatID string) (store.BotChat, bool, error) {
	chat, err := a.store.Chat(ctx, provider, chatID)
	if err != nil || chat.UserID == nil {
		return chat, false, err
	}
	if chat.SignedInAt != nil && a.now().Sub(*chat.SignedInAt) > a.limits.SessionTTL {
		if err := a.store.SignOut(ctx, provider, chatID); err != nil {
			return chat, false, err
		}
		chat.UserID = nil
		return chat, false, nil
	}
	return chat, true, nil
}

func (a *Auth) SignOut(ctx context.Context, provider, chatID string) error {
	return a.store.SignOut(ctx, provider, chatID)
}

func (a *Auth) hash(provider, chatID, code string) []byte {
	mac := hmac.New(sha256.New, a.key)
	mac.Write([]byte(provider + "\x00" + chatID + "\x00" + code))
	return mac.Sum(nil)
}

const codeDigits = 6

func newCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1_000_000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

// normalizeEmail matches how registration stores addresses: trimmed,
// lower-cased, and a bare address only.
func normalizeEmail(input string) (string, bool) {
	email := strings.ToLower(strings.TrimSpace(input))
	if email == "" || len(email) > 254 {
		return "", false
	}
	address, err := mail.ParseAddress(email)
	if err != nil || address.Address != email || !strings.Contains(email[strings.LastIndex(email, "@"):], ".") {
		return "", false
	}
	return email, true
}

// normalizeCode accepts Persian and Arabic-Indic digits and stray spaces, as
// typed on a Persian keyboard.
func normalizeCode(input string) (string, bool) {
	var b strings.Builder
	for _, r := range input {
		switch {
		case r >= '0' && r <= '9':
			b.WriteRune(r)
		case r >= '۰' && r <= '۹':
			b.WriteRune('0' + r - '۰')
		case r >= '٠' && r <= '٩':
			b.WriteRune('0' + r - '٠')
		case unicode.IsSpace(r) || r == '-':
		default:
			return "", false
		}
	}
	return b.String(), b.Len() == codeDigits
}

// MaskEmail shows enough of an address to recognize it: "m***@gmail.com".
func MaskEmail(email string) string {
	local, domain, ok := strings.Cut(email, "@")
	if !ok || local == "" {
		return "***"
	}
	return string([]rune(local)[:1]) + "***@" + domain
}
