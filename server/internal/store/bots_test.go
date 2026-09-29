package store

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestBotLoginCodeSignsTheChatIn(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	user, err := NewUsers(pool).Create(ctx, "bot@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	bots := NewBots(pool)
	now := time.Now()

	chat, err := bots.Chat(ctx, "bale", "42")
	if err != nil || chat.State != ChatIdle || chat.UserID != nil {
		t.Fatalf("unseen chat = %+v, %v", chat, err)
	}
	if err := bots.AddCode(ctx, LoginCode{
		Provider: "bale", ChatID: "42", Email: "bot@example.com", UserID: &user.ID,
		CodeHash: []byte("right"), ExpiresAt: now.Add(time.Minute),
	}); err != nil {
		t.Fatal(err)
	}
	if chat, _ := bots.Chat(ctx, "bale", "42"); chat.State != ChatAwaitingCode {
		t.Fatalf("state after code = %s", chat.State)
	}

	if _, err := bots.VerifyCode(ctx, "bale", "42", []byte("wrong"), now, 5); !errors.Is(err, ErrCodeInvalid) {
		t.Fatalf("wrong code: %v", err)
	}
	if _, err := bots.VerifyCode(ctx, "telegram", "42", []byte("right"), now, 5); !errors.Is(err, ErrCodeInvalid) {
		t.Fatalf("code from another provider's chat: %v", err)
	}
	userID, err := bots.VerifyCode(ctx, "bale", "42", []byte("right"), now, 5)
	if err != nil || userID != user.ID {
		t.Fatalf("right code = %q, %v", userID, err)
	}
	chat, _ = bots.Chat(ctx, "bale", "42")
	if chat.UserID == nil || *chat.UserID != user.ID || chat.State != ChatIdle {
		t.Fatalf("signed-in chat = %+v", chat)
	}
	if _, err := bots.VerifyCode(ctx, "bale", "42", []byte("right"), now, 5); !errors.Is(err, ErrCodeInvalid) {
		t.Fatalf("reused code: %v", err)
	}

	if err := bots.SignOut(ctx, "bale", "42"); err != nil {
		t.Fatal(err)
	}
	if chat, _ := bots.Chat(ctx, "bale", "42"); chat.UserID != nil {
		t.Fatalf("chat still signed in after sign-out: %+v", chat)
	}
}

func TestBotLoginCodeExpiresAndLimitsAttempts(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	user, _ := NewUsers(pool).Create(ctx, "bot@example.com", "hash")
	bots := NewBots(pool)
	now := time.Now()
	add := func() {
		t.Helper()
		if err := bots.AddCode(ctx, LoginCode{
			Provider: "bale", ChatID: "1", Email: "bot@example.com", UserID: &user.ID,
			CodeHash: []byte("right"), ExpiresAt: now.Add(time.Minute),
		}); err != nil {
			t.Fatal(err)
		}
	}

	add()
	if _, err := bots.VerifyCode(ctx, "bale", "1", []byte("right"), now.Add(2*time.Minute), 3); !errors.Is(err, ErrCodeInvalid) {
		t.Fatalf("expired code: %v", err)
	}

	add()
	bots.VerifyCode(ctx, "bale", "1", []byte("x"), now, 3)
	bots.VerifyCode(ctx, "bale", "1", []byte("x"), now, 3)
	if _, err := bots.VerifyCode(ctx, "bale", "1", []byte("x"), now, 3); !errors.Is(err, ErrCodeAttempts) {
		t.Fatalf("third wrong code: %v", err)
	}
	if _, err := bots.VerifyCode(ctx, "bale", "1", []byte("right"), now, 3); !errors.Is(err, ErrCodeAttempts) {
		t.Fatalf("right code after too many attempts: %v", err)
	}

	// A new code replaces the dead one.
	add()
	if _, err := bots.VerifyCode(ctx, "bale", "1", []byte("right"), now, 3); err != nil {
		t.Fatalf("fresh code: %v", err)
	}
}

func TestBotCodeForUnknownEmailNeverVerifies(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	bots := NewBots(pool)
	now := time.Now()
	if err := bots.AddCode(ctx, LoginCode{
		Provider: "bale", ChatID: "1", Email: "nobody@example.com",
		CodeHash: []byte("right"), ExpiresAt: now.Add(time.Minute),
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := bots.VerifyCode(ctx, "bale", "1", []byte("right"), now, 5); !errors.Is(err, ErrCodeInvalid) {
		t.Fatalf("unknown email: %v", err)
	}

	forChat, forEmail, last, err := bots.CodesSince(ctx, "bale", "1", "nobody@example.com", now.Add(-time.Hour))
	if err != nil || forChat != 1 || forEmail != 1 || last == nil {
		t.Fatalf("CodesSince = %d, %d, %v, %v", forChat, forEmail, last, err)
	}
}

func TestBotUpdatesAndImportsAreDeduplicated(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	user, _ := NewUsers(pool).Create(ctx, "bot@example.com", "hash")
	bots := NewBots(pool)

	first, err := bots.FirstDelivery(ctx, "bale", "100")
	again, _ := bots.FirstDelivery(ctx, "bale", "100")
	other, _ := bots.FirstDelivery(ctx, "telegram", "100")
	if err != nil || !first || again || !other {
		t.Fatalf("deliveries: %v %v %v %v", first, again, other, err)
	}

	job := BotImport{
		Provider: "bale", ChatID: "1", MessageID: "7", UserID: user.ID,
		FileID: "f", FileName: "song.mp3", SizeBytes: 10,
	}
	created, err := bots.AddImport(ctx, job)
	if err != nil || created.State != ImportQueued {
		t.Fatalf("AddImport = %+v, %v", created, err)
	}
	if _, err := bots.AddImport(ctx, job); !errors.Is(err, ErrDuplicateImport) {
		t.Fatalf("second AddImport: %v", err)
	}

	claimed, ok, err := bots.StartImport(ctx, created.ID, time.Now().Add(-time.Hour))
	if err != nil || !ok || claimed.Attempts != 1 || claimed.State != ImportDownloading {
		t.Fatalf("StartImport = %+v, %v, %v", claimed, ok, err)
	}
	if _, ok, _ := bots.StartImport(ctx, created.ID, time.Now().Add(-time.Hour)); ok {
		t.Fatal("an import in progress was claimed twice")
	}
	// After a crash, a stale download can be claimed again.
	if _, ok, _ := bots.StartImport(ctx, created.ID, time.Now().Add(time.Hour)); !ok {
		t.Fatal("stale import was not reclaimable")
	}

	unfinished, err := bots.UnfinishedImports(ctx, 10)
	if err != nil || len(unfinished) != 1 {
		t.Fatalf("UnfinishedImports = %v, %v", unfinished, err)
	}
	reason := "invalid_audio"
	if err := bots.FinishImport(ctx, created.ID, nil, &reason); err != nil {
		t.Fatal(err)
	}
	if unfinished, _ := bots.UnfinishedImports(ctx, 10); len(unfinished) != 0 {
		t.Fatalf("finished import still unfinished: %v", unfinished)
	}
}
