package bot

import (
	"context"
	"errors"
	"log/slog"
	"strings"

	"github.com/mhdolatabadi/nafir/server/internal/store"
)

type UpdateStore interface {
	FirstDelivery(ctx context.Context, provider, updateID string) (bool, error)
}

type UserLookup interface {
	ByID(ctx context.Context, id string) (store.User, error)
}

// Service is one provider's bot: it answers commands, links chats to
// accounts and hands audio to the importer.
type Service struct {
	provider Provider
	updates  UpdateStore
	linker   *Linker
	users    UserLookup
	importer *Importer
	metrics  *Metrics
	// imports runs import work outside the webhook request; tests replace it.
	imports func(func())
}

func NewService(p Provider, updates UpdateStore, linker *Linker, users UserLookup, importer *Importer) *Service {
	return &Service{
		provider: p, updates: updates, linker: linker, users: users, importer: importer,
		metrics: &Metrics{}, imports: func(work func()) { go work() },
	}
}

func (s *Service) Provider() Provider { return s.provider }

// Metrics counts what this bot has done since the API started.
func (s *Service) Metrics() *Metrics { return s.metrics }

// Handle processes one update. Redelivered updates are ignored.
func (s *Service) Handle(ctx context.Context, u Update) error {
	s.metrics.Updates.Add(1)
	first, err := s.updates.FirstDelivery(ctx, s.provider.Name(), u.ID)
	if err != nil || !first {
		if err == nil {
			s.metrics.Duplicates.Add(1)
		}
		return err
	}
	if u.ChatID == "" {
		return nil
	}
	if !u.Private {
		if u.File != nil || strings.HasPrefix(u.Text, "/") {
			return s.reply(ctx, u, msgPrivateOnly)
		}
		return nil
	}
	if u.File != nil {
		return s.handleFile(ctx, u)
	}
	text := strings.TrimSpace(u.Text)
	if command, argument, ok := parseCommand(text); ok {
		return s.handleCommand(ctx, u, command, argument)
	}
	// A code on its own links the chat, even one that is already linked:
	// that is how it moves to another account.
	if _, ok := NormalizeCode(text); ok {
		return s.link(ctx, u, text)
	}
	_, linked, err := s.linker.Session(ctx, s.provider.Name(), u.ChatID)
	if err != nil {
		return s.fail(ctx, u, err)
	}
	if !linked {
		return s.reply(ctx, u, msgNotLinked)
	}
	return s.reply(ctx, u, msgSendAudio)
}

func (s *Service) handleCommand(ctx context.Context, u Update, command, argument string) error {
	switch command {
	case "start":
		// Deep links arrive as "/start <code>".
		if argument != "" {
			return s.link(ctx, u, argument)
		}
		if _, linked, err := s.linker.Session(ctx, s.provider.Name(), u.ChatID); err != nil {
			return s.fail(ctx, u, err)
		} else if linked {
			return s.status(ctx, u)
		}
		return s.reply(ctx, u, msgWelcome)
	case "login", "link":
		if argument != "" {
			return s.link(ctx, u, argument)
		}
		return s.reply(ctx, u, msgHowToLink)
	case "logout", "unlink":
		if err := s.linker.Unlink(ctx, s.provider.Name(), u.ChatID); err != nil {
			return s.fail(ctx, u, err)
		}
		return s.reply(ctx, u, msgUnlinked)
	case "status":
		return s.status(ctx, u)
	default:
		return s.reply(ctx, u, msgHelp)
	}
}

func (s *Service) status(ctx context.Context, u Update) error {
	chat, linked, err := s.linker.Session(ctx, s.provider.Name(), u.ChatID)
	if err != nil {
		return s.fail(ctx, u, err)
	}
	if !linked {
		return s.reply(ctx, u, msgNotLinked)
	}
	user, err := s.users.ByID(ctx, *chat.UserID)
	if err != nil {
		return s.fail(ctx, u, err)
	}
	return s.reply(ctx, u, msgStatus(MaskEmail(user.Email)))
}

func (s *Service) link(ctx context.Context, u Update, code string) error {
	userID, err := s.linker.Redeem(ctx, s.provider.Name(), u.ChatID, code)
	if err == nil {
		s.metrics.Links.Add(1)
	} else {
		s.metrics.LinkFailures.Add(1)
	}
	switch {
	case errors.Is(err, ErrBadCode):
		return s.reply(ctx, u, msgBadCode)
	case errors.Is(err, ErrLocked):
		return s.reply(ctx, u, msgLocked)
	case err != nil:
		return s.fail(ctx, u, err)
	}
	user, err := s.users.ByID(ctx, userID)
	if err != nil {
		return s.fail(ctx, u, err)
	}
	return s.reply(ctx, u, msgLinked(MaskEmail(user.Email)))
}

func (s *Service) handleFile(ctx context.Context, u Update) error {
	chat, linked, err := s.linker.Session(ctx, s.provider.Name(), u.ChatID)
	if err != nil {
		return s.fail(ctx, u, err)
	}
	if !linked {
		return s.reply(ctx, u, msgNotLinked)
	}
	if reason := s.importer.Check(s.provider, *u.File); reason != "" {
		return s.reply(ctx, u, s.refused(reason))
	}
	job, err := s.importer.Queue(ctx, s.provider, u, *chat.UserID)
	if errors.Is(err, store.ErrDuplicateImport) {
		return nil
	}
	if err != nil {
		return s.fail(ctx, u, err)
	}
	if err := s.reply(ctx, u, msgQueued); err != nil {
		slog.Warn("bot reply failed", "provider", s.provider.Name(), "error", err)
	}
	s.imports(func() { s.runImport(context.WithoutCancel(ctx), job.ID, false) })
	return nil
}

// Resume restarts imports a shutdown interrupted.
func (s *Service) Resume(ctx context.Context) {
	jobs, err := s.importer.Unfinished(ctx)
	if err != nil {
		slog.Error("list unfinished bot imports", "provider", s.provider.Name(), "error", err)
		return
	}
	for _, job := range jobs {
		if job.Provider == s.provider.Name() {
			s.imports(func() { s.runImport(ctx, job.ID, true) })
		}
	}
}

func (s *Service) runImport(ctx context.Context, id string, interrupted bool) {
	result, ok := s.importer.Run(ctx, s.provider, id, interrupted)
	if !ok {
		return
	}
	text := s.refused(result.Reason)
	if result.Track != nil {
		text = msgImported(result.Track.Title)
		s.metrics.ImportsDone.Add(1)
	} else {
		s.metrics.ImportsFailed.Add(1)
	}
	if err := s.provider.Send(ctx, result.Import.ChatID, text); err != nil {
		s.metrics.ReplyFailures.Add(1)
		slog.Warn("bot import reply failed", "provider", s.provider.Name(), "error", err)
	}
}

func (s *Service) refused(reason string) string {
	limit := min(s.importer.policy.MaxFileBytes, s.provider.MaxDownloadBytes())
	return msgRefused(reason, limit>>20)
}

func (s *Service) reply(ctx context.Context, u Update, text string) error {
	err := s.provider.Send(ctx, u.ChatID, text)
	if err != nil {
		s.metrics.ReplyFailures.Add(1)
	}
	return err
}

// fail tells the chat something went wrong and returns the cause for logging.
func (s *Service) fail(ctx context.Context, u Update, cause error) error {
	if err := s.reply(ctx, u, msgTryAgain); err != nil {
		return errors.Join(cause, err)
	}
	return cause
}

// parseCommand reads "/start@NafirBot 1234" as "start" with argument "1234".
func parseCommand(text string) (command, argument string, ok bool) {
	if !strings.HasPrefix(text, "/") {
		return "", "", false
	}
	head, argument, _ := strings.Cut(text, " ")
	command, _, _ = strings.Cut(head[1:], "@")
	return strings.ToLower(command), strings.TrimSpace(argument), command != ""
}
