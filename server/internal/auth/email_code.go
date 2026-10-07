package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"math/big"
)

// EmailCodeDigits is the length of an email verification code.
const EmailCodeDigits = 6

// EmailCodes draws email verification codes and hashes them for storage.
// The hash is keyed with a server secret and bound to the account and
// address, so a leaked database row can't be brute-forced offline and a
// code for one account or address is worthless for another.
type EmailCodes struct {
	key []byte
}

func NewEmailCodes(secret []byte) (*EmailCodes, error) {
	if len(secret) < MinSecretBytes {
		return nil, errors.New("email code secret must be at least 32 bytes")
	}
	// A key of its own, so these hashes never coincide with anything else
	// the same secret signs.
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte("nafir email verification code v1"))
	return &EmailCodes{key: mac.Sum(nil)}, nil
}

// New draws a uniformly random code of EmailCodeDigits digits.
func (c *EmailCodes) New() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1_000_000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

// Hash is what is stored for code, sent to email for userID.
func (c *EmailCodes) Hash(userID, email, code string) string {
	mac := hmac.New(sha256.New, c.key)
	// Lengths first, so no two different inputs run together the same way.
	fmt.Fprintf(mac, "%d:%s|%d:%s|%s", len(userID), userID, len(email), email, code)
	return hex.EncodeToString(mac.Sum(nil))
}

// Matches compares code with a stored hash in constant time.
func (c *EmailCodes) Matches(userID, email, code, hash string) bool {
	return hmac.Equal([]byte(c.Hash(userID, email, code)), []byte(hash))
}
