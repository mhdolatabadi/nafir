package bot

import (
	"context"
	"errors"
	"log/slog"
	"strings"

	"github.com/mhdolatabadi/nafir/server/internal/store"
)

type ChatStore interface {
	SetState(ctx context.Context, provider, chatID string, state store.ChatState) error
	FirstDelivery(ctx context.Context, provider, updateID string) (bool, error)
}

// Service is one provider's bot: it answers commands, runs the login flow and
// hands audio to the importer.
type Service struct {
	provider Provider
	chats    ChatStore
	auth     *Auth
	users    UserLookup
	importer *Importer
	// imports runs import work outside the webhook request; tests replace it.
	imports func(func())
}

func NewService(p Provider, chats ChatStore, auth *Auth, users UserLookup, importer *Importer) *Service {
	return &Service{
		provider: p, chats: chats, auth: auth, users: users, importer: importer,
		imports: func(work func()) { go work() },
	}
}

func (s *Service) Provider() Provider { return s.provider }

// Handle processes one update. Redelivered updates are ignored.
func (s *Service) Handle(ctx context.Context, u Update) error {
	first, err := s.chats.FirstDelivery(ctx, s.provider.Name(), u.ID)
	if err != nil || !first {
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
	if command, ok := parseCommand(text); ok {
		return s.handleCommand(ctx, u, command)
	}
	chat, _, err := s.auth.Session(ctx, s.provider.Name(), u.ChatID)
	if err != nil {
		return s.fail(ctx, u, err)
	}
	switch chat.State {
	case store.ChatAwaitingEmail:
		return s.requestCode(ctx, u, text)
	case store.ChatAwaitingCode:
		return s.verifyCode(ctx, u, text)
	}
	if chat.UserID == nil {
		return s.reply(ctx, u, msgNotSignedIn)
	}
	return s.reply(ctx, u, msgSendAudio)
}

func (s *Service) handleCommand(ctx context.Context, u Update, command string) error {
	name := s.provider.Name()
	switch command {
	case "start":
		if _, signedIn, err := s.auth.Session(ctx, name, u.ChatID); err != nil {
			return s.fail(ctx, u, err)
		} else if signedIn {
			return s.status(ctx, u)
		}
		if err := s.chats.SetState(ctx, name, u.ChatID, store.ChatAwaitingEmail); err != nil {
			return s.fail(ctx, u, err)
		}
		return s.reply(ctx, u, msgWelcome)
	case "login":
		// Signing in again, even to another account, always takes a new code.
		if err := s.chats.SetState(ctx, name, u.ChatID, store.ChatAwaitingEmail); err != nil {
			return s.fail(ctx, u, err)
		}
		return s.reply(ctx, u, msgAskEmail)
	case "logout":
		if err := s.auth.SignOut(ctx, name, u.ChatID); err != nil {
			return s.fail(ctx, u, err)
		}
		return s.reply(ctx, u, msgSignedOut)
	case "status":
		return s.status(ctx, u)
	default:
		return s.reply(ctx, u, msgHelp)
	}
}

func (s *Service) status(ctx context.Context, u Update) error {
	chat, signedIn, err := s.auth.Session(ctx, s.provider.Name(), u.ChatID)
	if err != nil {
		return s.fail(ctx, u, err)
	}
	if !signedIn {
		return s.reply(ctx, u, msgNotSignedIn)
	}
	user, err := s.users.ByID(ctx, *chat.UserID)
	if err != nil {
		return s.fail(ctx, u, err)
	}
	return s.reply(ctx, u, msgStatus(MaskEmail(user.Email)))
}

func (s *Service) requestCode(ctx context.Context, u Update, email string) error {
	err := s.auth.RequestCode(ctx, s.provider.Name(), u.ChatID, email)
	var wait WaitError
	switch {
	case err == nil:
		return s.reply(ctx, u, msgCodeSent)
	case errors.Is(err, ErrBadEmail):
		return s.reply(ctx, u, msgBadEmail)
	case errors.As(err, &wait):
		return s.reply(ctx, u, msgWait(int(wait.Retry.Seconds())+1))
	case errors.Is(err, ErrThrottled):
		return s.reply(ctx, u, msgThrottled)
	default:
		return s.fail(ctx, u, err)
	}
}

func (s *Service) verifyCode(ctx context.Context, u Update, code string) error {
	userID, err := s.auth.VerifyCode(ctx, s.provider.Name(), u.ChatID, code)
	if errors.Is(err, ErrBadCode) {
		return s.reply(ctx, u, msgBadCode)
	}
	if err != nil {
		return s.fail(ctx, u, err)
	}
	user, err := s.users.ByID(ctx, userID)
	if err != nil {
		return s.fail(ctx, u, err)
	}
	return s.reply(ctx, u, msgSignedIn(MaskEmail(user.Email)))
}

func (s *Service) handleFile(ctx context.Context, u Update) error {
	chat, signedIn, err := s.auth.Session(ctx, s.provider.Name(), u.ChatID)
	if err != nil {
		return s.fail(ctx, u, err)
	}
	if !signedIn {
		return s.reply(ctx, u, msgNotSignedIn)
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
	}
	if err := s.provider.Send(ctx, result.Import.ChatID, text); err != nil {
		slog.Warn("bot import reply failed", "provider", s.provider.Name(), "error", err)
	}
}

func (s *Service) refused(reason string) string {
	limit := min(s.importer.policy.MaxFileBytes, s.provider.MaxDownloadBytes())
	return msgRefused(reason, limit>>20)
}

func (s *Service) reply(ctx context.Context, u Update, text string) error {
	return s.provider.Send(ctx, u.ChatID, text)
}

// fail tells the chat something went wrong and returns the cause for logging.
func (s *Service) fail(ctx context.Context, u Update, cause error) error {
	if err := s.reply(ctx, u, msgTryAgain); err != nil {
		return errors.Join(cause, err)
	}
	return cause
}

// parseCommand reads "/start" or "/start@NafirBot extra" as "start".
func parseCommand(text string) (string, bool) {
	if !strings.HasPrefix(text, "/") {
		return "", false
	}
	command, _, _ := strings.Cut(strings.Fields(text)[0][1:], "@")
	return strings.ToLower(command), command != ""
}
