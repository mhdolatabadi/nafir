package bot

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"path"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/store"
)

var (
	ErrUnknownProvider = errors.New("no such bot")
	ErrTrackNotFound   = errors.New("track not found")
	ErrNotLinked       = errors.New("no chat is linked with this bot")
	ErrTrackTooLarge   = errors.New("track is too large for the bot to send")
)

type SendStore interface {
	LinkedChats(ctx context.Context, userID, provider string, since time.Time) ([]string, error)
	TrackFileID(ctx context.Context, provider, trackID string) (string, error)
	SaveTrackFileID(ctx context.Context, provider, trackID, fileID string) error
}

type TrackReader interface {
	ForOwner(ctx context.Context, ownerID, trackID string) (store.Track, error)
}

type ObjectReader interface {
	Open(ctx context.Context, key string) (io.ReadCloser, error)
}

// Sender has a bot post the user's own tracks into the chats they linked,
// where they can be played or forwarded. Uploads run in the background, a
// few at a time; each provider file ID is kept so the next send of the same
// track is instant.
type Sender struct {
	provider   Provider
	store      SendStore
	tracks     TrackReader
	objects    ObjectReader
	sessionTTL time.Duration
	metrics    *Metrics
	now        func() time.Time
	slots      chan struct{}
	// run starts delivery outside the request; tests replace it.
	run func(func())
}

func NewSender(p Provider, s SendStore, tracks TrackReader, objects ObjectReader, sessionTTL time.Duration, concurrency int) *Sender {
	return &Sender{
		provider: p, store: s, tracks: tracks, objects: objects, sessionTTL: sessionTTL,
		metrics: &Metrics{}, now: time.Now, slots: make(chan struct{}, concurrency),
		run: func(work func()) { go work() },
	}
}

// CountInto makes the sender count its deliveries in m, usually the bot
// service's metrics.
func (s *Sender) CountInto(m *Metrics) *Sender {
	s.metrics = m
	return s
}

// Send checks that the track can be sent and queues it for every chat the
// user linked with this bot. Failures after that are reported in the chat.
func (s *Sender) Send(ctx context.Context, userID, trackID string) error {
	track, err := s.tracks.ForOwner(ctx, userID, trackID)
	if errors.Is(err, store.ErrNotFound) || (err == nil && track.Status != store.TrackReady) {
		return ErrTrackNotFound
	}
	if err != nil {
		return err
	}
	chats, err := s.store.LinkedChats(ctx, userID, s.provider.Name(), s.now().Add(-s.sessionTTL))
	if err != nil {
		return err
	}
	if len(chats) == 0 {
		return ErrNotLinked
	}
	fileID, err := s.store.TrackFileID(ctx, s.provider.Name(), track.ID)
	if err != nil {
		return err
	}
	if fileID == "" && track.SizeBytes > s.provider.MaxUploadBytes() {
		return ErrTrackTooLarge
	}
	background := context.WithoutCancel(ctx)
	s.run(func() {
		for _, chat := range chats {
			s.deliver(background, chat, track)
		}
	})
	return nil
}

func (s *Sender) deliver(ctx context.Context, chatID string, track store.Track) {
	s.slots <- struct{}{}
	defer func() { <-s.slots }()
	name := s.provider.Name()
	audio := OutgoingAudio{Title: track.Title, FileName: path.Base(track.StorageKey)}
	if track.Artist != nil {
		audio.Performer = *track.Artist
	}

	// Reuse the provider's copy when there is one; if it no longer works,
	// upload the audio again.
	if fileID, err := s.store.TrackFileID(ctx, name, track.ID); err == nil && fileID != "" {
		audio.FileID = fileID
		_, err := s.provider.SendAudio(ctx, chatID, audio)
		if err == nil {
			s.metrics.SendsDone.Add(1)
			return
		}
		slog.Warn("bot resend by file ID failed, uploading", "provider", name, "error", err)
		audio.FileID = ""
	}

	err := s.upload(ctx, chatID, track, audio)
	if err == nil {
		s.metrics.SendsDone.Add(1)
		return
	}
	s.metrics.SendsFailed.Add(1)
	slog.Error("bot send failed", "provider", name, "track", track.ID, "error", err)
	text := msgSendFailed(track.Title)
	if errors.Is(err, ErrFileTooLarge) {
		text = msgSendTooLarge(track.Title, s.provider.MaxUploadBytes()>>20)
	}
	if err := s.provider.Send(ctx, chatID, text); err != nil {
		slog.Warn("bot send-failure reply failed", "provider", name, "error", err)
	}
}

func (s *Sender) upload(ctx context.Context, chatID string, track store.Track, audio OutgoingAudio) error {
	body, err := s.objects.Open(ctx, track.StorageKey)
	if err != nil {
		return err
	}
	defer body.Close()
	audio.Body, audio.Size = body, track.SizeBytes
	fileID, err := s.provider.SendAudio(ctx, chatID, audio)
	if err != nil {
		return err
	}
	if fileID != "" {
		if err := s.store.SaveTrackFileID(ctx, s.provider.Name(), track.ID, fileID); err != nil {
			slog.Warn("save bot file ID", "provider", s.provider.Name(), "error", err)
		}
	}
	return nil
}

// Senders routes sends to each provider's Sender.
type Senders map[string]*Sender

func (s Senders) Send(ctx context.Context, provider, userID, trackID string) error {
	sender, ok := s[provider]
	if !ok {
		return ErrUnknownProvider
	}
	return sender.Send(ctx, userID, trackID)
}
