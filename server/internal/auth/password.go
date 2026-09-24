package auth

import (
	"errors"

	"golang.org/x/crypto/bcrypt"
)

// MaxPasswordBytes is bcrypt's input limit; longer passwords are rejected rather than truncated.
const MaxPasswordBytes = 72

const MinPasswordLength = 8

var ErrPasswordMismatch = errors.New("password does not match")

type Passwords struct {
	Cost int
}

func (p Passwords) Hash(password string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), p.Cost)
	if err != nil {
		return "", err
	}
	return string(hash), nil
}

func (p Passwords) Verify(hash, password string) error {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	if errors.Is(err, bcrypt.ErrMismatchedHashAndPassword) {
		return ErrPasswordMismatch
	}
	return err
}
