// Package mail sends rhythmo's transactional email over SMTP.
package mail

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/tls"
	"encoding/hex"
	"errors"
	"fmt"
	"mime"
	"mime/quotedprintable"
	"net"
	"net/mail"
	"net/smtp"
	"strconv"
	"strings"
	"time"
)

// Message is one email with a plain-text body and an HTML alternative.
type Message struct {
	To      string
	Subject string
	Text    string
	HTML    string
}

// Sender delivers messages; *SMTP implements it.
type Sender interface {
	Send(ctx context.Context, message Message) error
}

// Config is the SMTP relay. Port 465 uses TLS from the start; any other
// port upgrades with STARTTLS, which is required whenever a password is
// sent to a host other than localhost.
type Config struct {
	Host     string
	Port     int
	Username string
	Password string
	From     string
}

type SMTP struct {
	config Config
	from   *mail.Address
	// tlsConfig is overridden by tests that run a local server.
	tlsConfig *tls.Config
}

// NewSMTP checks the configuration; nothing is dialled until Send.
func NewSMTP(config Config) (*SMTP, error) {
	if config.Host == "" {
		return nil, errors.New("SMTP host is required")
	}
	if config.Port <= 0 || config.Port > 65535 {
		return nil, fmt.Errorf("SMTP port %d is invalid", config.Port)
	}
	from, err := mail.ParseAddress(config.From)
	if err != nil {
		return nil, fmt.Errorf("sender address: %w", err)
	}
	if (config.Username == "") != (config.Password == "") {
		return nil, errors.New("SMTP username and password go together")
	}
	return &SMTP{config: config, from: from, tlsConfig: &tls.Config{ServerName: config.Host, MinVersion: tls.VersionTLS12}}, nil
}

// Send delivers one message, giving up when ctx ends.
func (s *SMTP) Send(ctx context.Context, message Message) error {
	to, err := mail.ParseAddress(message.To)
	if err != nil {
		return fmt.Errorf("recipient address: %w", err)
	}
	body, err := Build(s.from, to, message, time.Now())
	if err != nil {
		return err
	}
	address := net.JoinHostPort(s.config.Host, strconv.Itoa(s.config.Port))
	var dialer net.Dialer
	conn, err := dialer.DialContext(ctx, "tcp", address)
	if err != nil {
		return err
	}
	defer conn.Close()
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}
	stop := context.AfterFunc(ctx, func() { _ = conn.SetDeadline(time.Now()) })
	defer stop()
	if s.config.Port == 465 {
		conn = tls.Client(conn, s.tlsConfig)
	}
	client, err := smtp.NewClient(conn, s.config.Host)
	if err != nil {
		return err
	}
	defer client.Close()
	if s.config.Port != 465 {
		if ok, _ := client.Extension("STARTTLS"); ok {
			if err := client.StartTLS(s.tlsConfig); err != nil {
				return err
			}
		}
	}
	if s.config.Username != "" {
		// PlainAuth refuses to send the password without TLS, except to
		// localhost.
		if err := client.Auth(smtp.PlainAuth("", s.config.Username, s.config.Password, s.config.Host)); err != nil {
			return err
		}
	}
	if err := client.Mail(s.from.Address); err != nil {
		return err
	}
	if err := client.Rcpt(to.Address); err != nil {
		return err
	}
	writer, err := client.Data()
	if err != nil {
		return err
	}
	if _, err := writer.Write(body); err != nil {
		return err
	}
	if err := writer.Close(); err != nil {
		return err
	}
	return client.Quit()
}

// Build renders a multipart/alternative message: plain text first, then
// HTML, both UTF-8 and quoted-printable, with an encoded subject.
func Build(from, to *mail.Address, message Message, now time.Time) ([]byte, error) {
	var random [12]byte
	if _, err := rand.Read(random[:]); err != nil {
		return nil, err
	}
	boundary := "rhythmo-" + hex.EncodeToString(random[:])
	var b bytes.Buffer
	header := func(name, value string) {
		b.WriteString(name + ": " + value + "\r\n")
	}
	header("From", from.String())
	header("To", to.String())
	header("Subject", mime.QEncoding.Encode("utf-8", message.Subject))
	header("Date", now.UTC().Format(time.RFC1123Z))
	header("Message-ID", "<"+hex.EncodeToString(random[:])+"@"+domain(from.Address)+">")
	header("MIME-Version", "1.0")
	header("Content-Type", `multipart/alternative; boundary="`+boundary+`"`)
	b.WriteString("\r\n")
	for _, part := range []struct{ kind, body string }{
		{"text/plain", message.Text},
		{"text/html", message.HTML},
	} {
		b.WriteString("--" + boundary + "\r\n")
		header("Content-Type", part.kind+"; charset=utf-8")
		header("Content-Transfer-Encoding", "quoted-printable")
		b.WriteString("\r\n")
		encoder := quotedprintable.NewWriter(&b)
		if _, err := encoder.Write([]byte(strings.ReplaceAll(part.body, "\n", "\r\n"))); err != nil {
			return nil, err
		}
		if err := encoder.Close(); err != nil {
			return nil, err
		}
		b.WriteString("\r\n")
	}
	b.WriteString("--" + boundary + "--\r\n")
	return b.Bytes(), nil
}

func domain(address string) string {
	if at := strings.LastIndex(address, "@"); at >= 0 {
		return address[at+1:]
	}
	return "localhost"
}
