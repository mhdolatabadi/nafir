package mail

import (
	"mime"
	"net/mail"
	"strings"
	"testing"
	"time"
)

func TestMessageEncodesPersianSubjectAndBody(t *testing.T) {
	from := &mail.Address{Name: "نفیر", Address: "no-reply@example.com"}
	msg := string(Message(from, "a@example.com", "کد ورود نفیر", "کد: ۱۲۳\nخط دوم", time.Unix(0, 0)))

	parsed, err := mail.ReadMessage(strings.NewReader(msg))
	if err != nil {
		t.Fatal(err)
	}
	subject, err := new(mime.WordDecoder).DecodeHeader(parsed.Header.Get("Subject"))
	if err != nil || subject != "کد ورود نفیر" {
		t.Fatalf("subject = %q, %v", subject, err)
	}
	if !strings.Contains(msg, "کد: ۱۲۳\r\nخط دوم\r\n") {
		t.Fatalf("body lines are not CRLF: %q", msg)
	}
}

func TestNewSMTPRequiresHostAndSender(t *testing.T) {
	if _, err := NewSMTP(Config{Port: 587, From: "a@example.com"}); err == nil {
		t.Fatal("missing host accepted")
	}
	if _, err := NewSMTP(Config{Host: "smtp.example.com", Port: 587, From: "not an address"}); err == nil {
		t.Fatal("bad sender accepted")
	}
}
