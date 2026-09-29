// Package bot lets people sign in to Nafir and import audio from messenger
// bots. It knows nothing about any one messenger: each is a Provider, and the
// same commands, login flow and import pipeline serve all of them.
package bot

import (
	"context"
	"errors"
	"io"
)

// Update is one incoming message, already reduced to what Nafir uses.
type Update struct {
	// ID is the provider's update ID; redeliveries repeat it.
	ID        string
	ChatID    string
	Private   bool
	MessageID string
	Text      string
	File      *File
}

// File is an audio file or document attached to a message.
type File struct {
	ID        string
	Name      string
	MIMEType  string
	SizeBytes int64
	// Title and Performer come from the messenger's audio metadata, if any.
	Title     string
	Performer string
}

// Provider is one messenger's Bot API.
type Provider interface {
	// Name identifies the provider in storage and URLs, for example "bale".
	Name() string
	Send(ctx context.Context, chatID, text string) error
	// Open streams a file. The size is the provider's, which the import trusts
	// only as far as storage verifies it.
	Open(ctx context.Context, fileID string) (io.ReadCloser, int64, error)
	// MaxDownloadBytes is the largest file the provider lets bots download.
	MaxDownloadBytes() int64
}

// ErrFileTooLarge is returned by Open for files the provider will not serve.
var ErrFileTooLarge = errors.New("file is too large for the provider to download")
