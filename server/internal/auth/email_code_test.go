package auth

import (
	"regexp"
	"strings"
	"testing"
)

func TestEmailCodesAreSixDigitsAndHashed(t *testing.T) {
	codes, err := NewEmailCodes([]byte(strings.Repeat("s", MinSecretBytes)))
	if err != nil {
		t.Fatal(err)
	}
	seen := map[string]bool{}
	for range 50 {
		code, err := codes.New()
		if err != nil {
			t.Fatal(err)
		}
		if !regexp.MustCompile(`^[0-9]{6}$`).MatchString(code) {
			t.Fatalf("code %q is not six digits", code)
		}
		seen[code] = true
	}
	if len(seen) < 45 {
		t.Fatalf("only %d distinct codes in 50 draws", len(seen))
	}

	hash := codes.Hash("user-1", "a@example.com", "123456")
	if strings.Contains(hash, "123456") || len(hash) != 64 {
		t.Fatalf("hash %q reveals the code or has the wrong size", hash)
	}
	if !codes.Matches("user-1", "a@example.com", "123456", hash) {
		t.Fatal("the right code does not match")
	}
	for _, other := range [][3]string{
		{"user-1", "a@example.com", "123457"},
		{"user-2", "a@example.com", "123456"},
		{"user-1", "b@example.com", "123456"},
	} {
		if codes.Matches(other[0], other[1], other[2], hash) {
			t.Fatalf("%v matches a hash for another code, account or address", other)
		}
	}
	otherKey, _ := NewEmailCodes([]byte(strings.Repeat("t", MinSecretBytes)))
	if otherKey.Matches("user-1", "a@example.com", "123456", hash) {
		t.Fatal("a hash made with another secret matches")
	}
	if _, err := NewEmailCodes([]byte("short")); err == nil {
		t.Fatal("a short secret was accepted")
	}
}
