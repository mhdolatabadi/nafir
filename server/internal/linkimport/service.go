package linkimport

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"log/slog"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/bot"
	"github.com/mhdolatabadi/nafir/server/internal/store"
)

// More reasons a link is refused.
var (
	ErrDuplicate = errors.New("this link is already being imported")
	ErrTooMany   = errors.New("too many imports in progress")
	ErrDisabled  = errors.New("uploads are disabled")
)

// ImportStore records link imports next to the bots' ones.
type ImportStore interface {
	AddImport(ctx context.Context, i store.BotImport) (store.BotImport, error)
	ActiveImports(ctx context.Context, userID string) (int, error)
	ActiveImportFor(ctx context.Context, userID, provider, fileID string) (bool, error)
	RecentImports(ctx context.Context, userID, provider string, limit int) ([]store.BotImport, error)
}

// Service takes links from users and runs their imports in the background.
type Service struct {
	fetcher   *Fetcher
	provider  *Provider
	importer  *bot.Importer
	imports   ImportStore
	maxActive int
	// jobTimeout bounds one import's download and storage.
	jobTimeout time.Duration
	run        func(func())
}

func NewService(fetcher *Fetcher, provider *Provider, importer *bot.Importer, imports ImportStore, maxActive int) *Service {
	return &Service{
		fetcher: fetcher, provider: provider, importer: importer, imports: imports,
		maxActive: maxActive, jobTimeout: 15 * time.Minute, run: func(work func()) { go work() },
	}
}

// Preview lists the supported audio files a link leads to without queueing an
// import. Files the current upload policy refuses are left out.
func (s *Service) Preview(ctx context.Context, userID, rawURL string) ([]Candidate, error) {
	u, err := ParseURL(rawURL)
	if err != nil {
		return nil, err
	}
	candidates, err := s.fetcher.ResolveAll(ctx, u)
	if err != nil {
		return nil, err
	}
	result := make([]Candidate, 0, len(candidates))
	tooLarge := false
	for _, candidate := range candidates {
		switch s.importer.Check(s.provider, bot.File{Name: candidate.FileName, SizeBytes: candidate.SizeBytes}) {
		case "":
			result = append(result, candidate)
		case bot.ReasonTooLarge:
			tooLarge = true
		case bot.ReasonDisabled:
			return nil, ErrDisabled
		}
	}
	if len(result) == 0 {
		if tooLarge {
			return nil, ErrTooLarge
		}
		return nil, ErrUnsupported
	}
	return result, nil
}

// Submit finds the audio file a link leads to and queues its import. The
// errors are the package's refusal reasons, or an internal failure.
func (s *Service) Submit(ctx context.Context, userID, rawURL string) (store.BotImport, error) {
	u, err := ParseURL(rawURL)
	if err != nil {
		return store.BotImport{}, err
	}
	active, err := s.imports.ActiveImports(ctx, userID)
	if err != nil {
		return store.BotImport{}, err
	}
	if active >= s.maxActive {
		return store.BotImport{}, ErrTooMany
	}
	candidate, err := s.fetcher.Resolve(ctx, u)
	if err != nil {
		return store.BotImport{}, err
	}
	switch s.importer.Check(s.provider, bot.File{Name: candidate.FileName, SizeBytes: candidate.SizeBytes}) {
	case "":
	case bot.ReasonTooLarge:
		return store.BotImport{}, ErrTooLarge
	case bot.ReasonDisabled:
		return store.BotImport{}, ErrDisabled
	default:
		return store.BotImport{}, ErrUnsupported
	}
	fileURL := candidate.URL.String()
	if dup, err := s.imports.ActiveImportFor(ctx, userID, ProviderName, fileURL); err != nil {
		return store.BotImport{}, err
	} else if dup {
		return store.BotImport{}, ErrDuplicate
	}
	id := make([]byte, 16)
	if _, err := rand.Read(id); err != nil {
		return store.BotImport{}, err
	}
	job, err := s.imports.AddImport(ctx, store.BotImport{
		Provider: ProviderName, ChatID: userID, MessageID: hex.EncodeToString(id), UserID: userID,
		FileID: fileURL, FileName: candidate.FileName, SizeBytes: candidate.SizeBytes,
	})
	if err != nil {
		return store.BotImport{}, err
	}
	s.run(func() { s.runJob(context.Background(), job.ID, false) })
	return job, nil
}

func (s *Service) runJob(ctx context.Context, id string, interrupted bool) {
	ctx, cancel := context.WithTimeout(ctx, s.jobTimeout)
	defer cancel()
	if result, ok := s.importer.Run(ctx, s.provider, id, interrupted); ok && result.Reason != "" {
		// Never log the link itself: it may be private to the user.
		slog.Info("link import refused", "import", id, "reason", result.Reason)
	}
}

// Resume restarts link imports a shutdown interrupted.
func (s *Service) Resume(ctx context.Context) {
	jobs, err := s.importer.Unfinished(ctx)
	if err != nil {
		slog.Error("list unfinished link imports", "error", err)
		return
	}
	for _, job := range jobs {
		if job.Provider == ProviderName {
			s.run(func() { s.runJob(ctx, job.ID, true) })
		}
	}
}

// Recent lists the user's latest link imports, newest first.
func (s *Service) Recent(ctx context.Context, userID string) ([]store.BotImport, error) {
	return s.imports.RecentImports(ctx, userID, ProviderName, 20)
}
