package auth

import (
	_ "embed"
	"strings"
)

//go:embed common_passwords.txt
var commonPasswordList string

var commonPasswords = func() map[string]bool {
	set := make(map[string]bool)
	for _, line := range strings.Split(commonPasswordList, "\n") {
		if line = strings.TrimSpace(line); line != "" && !strings.HasPrefix(line, "#") {
			set[line] = true
		}
	}
	return set
}()

// WeakPassword reports whether password is too easy to guess for the account
// with this (normalized) email: one of the most common passwords, the email
// or its local part, or a single character repeated. It complements the
// length rule; it does not replace it.
func WeakPassword(password, email string) bool {
	lowered := strings.ToLower(strings.TrimSpace(password))
	if commonPasswords[lowered] {
		return true
	}
	if email != "" {
		local, _, _ := strings.Cut(email, "@")
		if lowered == email || lowered == local {
			return true
		}
	}
	runes := []rune(lowered)
	if len(runes) == 0 {
		return false
	}
	for _, r := range runes[1:] {
		if r != runes[0] {
			return false
		}
	}
	return true
}
