package auth

import (
	"context"
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const tokenIssuer = "nafir"

// MinSecretBytes keeps HS256 keys at least as long as the hash output.
const MinSecretBytes = 32

var ErrInvalidToken = errors.New("invalid access token")

type Tokens struct {
	secret   []byte
	ttl      time.Duration
	now      func() time.Time
	sessions *Sessions
}

func NewTokens(secret []byte, ttl time.Duration) (*Tokens, error) {
	if len(secret) < MinSecretBytes {
		return nil, errors.New("token secret must be at least 32 bytes")
	}
	if ttl <= 0 {
		return nil, errors.New("token lifetime must be positive")
	}
	return &Tokens{secret: secret, ttl: ttl, now: time.Now}, nil
}

// Issue returns a signed access token for userID and the moment it expires,
// for the account's first session epoch.
func (t *Tokens) Issue(userID string) (string, time.Time, error) {
	return t.IssueSession(userID, 0)
}

// IssueSession returns a token bound to the account's current session epoch;
// revoking the account's sessions moves the epoch on, which ends it (#216).
func (t *Tokens) IssueSession(userID string, epoch int64) (string, time.Time, error) {
	issuedAt := t.now()
	expiresAt := issuedAt.Add(t.ttl)
	claims := sessionClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    tokenIssuer,
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(issuedAt),
			ExpiresAt: jwt.NewNumericDate(expiresAt),
		},
		Epoch: epoch,
	}
	signed, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(t.secret)
	if err != nil {
		return "", time.Time{}, err
	}
	return signed, expiresAt, nil
}

// sessionClaims adds the session epoch; tokens issued before it existed
// carry none and count as epoch 0.
type sessionClaims struct {
	jwt.RegisteredClaims
	Epoch int64 `json:"sep,omitempty"`
}

// Verify checks the signature, issuer and expiry and returns the user ID.
// It does not check revocation; requests go through Authorize.
func (t *Tokens) Verify(token string) (string, error) {
	claims, err := t.parse(token)
	if err != nil {
		return "", err
	}
	return claims.Subject, nil
}

// Authorize is Verify plus the revocation check: with sessions configured,
// a token whose epoch is no longer the account's current one, or whose
// account no longer exists, is ErrInvalidToken. Any other error means the
// check itself failed and says nothing about the token.
func (t *Tokens) Authorize(ctx context.Context, token string) (string, error) {
	claims, err := t.parse(token)
	if err != nil {
		return "", err
	}
	if t.sessions != nil {
		if err := t.sessions.check(ctx, claims.Subject, claims.Epoch); err != nil {
			return "", err
		}
	}
	return claims.Subject, nil
}

// WithSessions turns on revocation checks in Authorize.
func (t *Tokens) WithSessions(sessions *Sessions) *Tokens {
	t.sessions = sessions
	return t
}

func (t *Tokens) parse(token string) (*sessionClaims, error) {
	claims := &sessionClaims{}
	_, err := jwt.ParseWithClaims(token, claims, func(*jwt.Token) (any, error) {
		return t.secret, nil
	},
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer(tokenIssuer),
		jwt.WithExpirationRequired(),
		jwt.WithTimeFunc(t.now),
	)
	if err != nil || claims.Subject == "" || claims.Epoch < 0 {
		return nil, ErrInvalidToken
	}
	return claims, nil
}
