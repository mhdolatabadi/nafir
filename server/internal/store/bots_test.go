package store

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestBotLinkCodeLinksTheChatOnce(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	user, err := NewUsers(pool).Create(ctx, "bot@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	bots := NewBots(pool)
	now := time.Now()

	chat, err := bots.Chat(ctx, "bale", "42")
	if err != nil || chat.UserID != nil {
		t.Fatalf("unseen chat = %+v, %v", chat, err)
	}
	if err := bots.CreateLinkCode(ctx, user.ID, []byte("right"), now.Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	if _, err := bots.RedeemLinkCode(ctx, "bale", "42", []byte("wrong"), now, 5, time.Hour); !errors.Is(err, ErrCodeInvalid) {
		t.Fatalf("wrong code: %v", err)
	}
	userID, err := bots.RedeemLinkCode(ctx, "bale", "42", []byte("right"), now, 5, time.Hour)
	if err != nil || userID != user.ID {
		t.Fatalf("right code = %q, %v", userID, err)
	}
	chat, _ = bots.Chat(ctx, "bale", "42")
	if chat.UserID == nil || *chat.UserID != user.ID || chat.LinkedAt == nil {
		t.Fatalf("linked chat = %+v", chat)
	}
	if _, err := bots.RedeemLinkCode(ctx, "bale", "43", []byte("right"), now, 5, time.Hour); !errors.Is(err, ErrCodeInvalid) {
		t.Fatalf("reused code: %v", err)
	}

	if err := bots.Unlink(ctx, "bale", "42"); err != nil {
		t.Fatal(err)
	}
	if chat, _ := bots.Chat(ctx, "bale", "42"); chat.UserID != nil {
		t.Fatalf("chat still linked after unlink: %+v", chat)
	}
}

func TestBotLinkCodesExpireAndAreReplaced(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	user, _ := NewUsers(pool).Create(ctx, "bot@example.com", "hash")
	other, _ := NewUsers(pool).Create(ctx, "other@example.com", "hash")
	bots := NewBots(pool)
	now := time.Now()

	bots.CreateLinkCode(ctx, user.ID, []byte("first"), now.Add(time.Minute))
	if _, err := bots.RedeemLinkCode(ctx, "bale", "1", []byte("first"), now.Add(2*time.Minute), 5, time.Hour); !errors.Is(err, ErrCodeInvalid) {
		t.Fatalf("expired code: %v", err)
	}

	bots.CreateLinkCode(ctx, user.ID, []byte("old"), now.Add(time.Minute))
	bots.CreateLinkCode(ctx, user.ID, []byte("new"), now.Add(time.Minute))
	if _, err := bots.RedeemLinkCode(ctx, "bale", "1", []byte("old"), now, 5, time.Hour); !errors.Is(err, ErrCodeInvalid) {
		t.Fatalf("replaced code: %v", err)
	}
	if err := bots.CreateLinkCode(ctx, other.ID, []byte("new"), now.Add(time.Minute)); !errors.Is(err, ErrCodeCollision) {
		t.Fatalf("colliding code: %v", err)
	}
	if id, err := bots.RedeemLinkCode(ctx, "bale", "1", []byte("new"), now, 5, time.Hour); err != nil || id != user.ID {
		t.Fatalf("new code = %q, %v", id, err)
	}
}

func TestBotChatIsLockedOutAfterWrongCodes(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	user, _ := NewUsers(pool).Create(ctx, "bot@example.com", "hash")
	bots := NewBots(pool)
	now := time.Now()
	bots.CreateLinkCode(ctx, user.ID, []byte("right"), now.Add(2*time.Hour))

	for i := 0; i < 2; i++ {
		bots.RedeemLinkCode(ctx, "bale", "1", []byte("x"), now, 3, time.Hour)
	}
	if _, err := bots.RedeemLinkCode(ctx, "bale", "1", []byte("x"), now, 3, time.Hour); !errors.Is(err, ErrCodeAttempts) {
		t.Fatalf("third wrong code: %v", err)
	}
	if _, err := bots.RedeemLinkCode(ctx, "bale", "1", []byte("right"), now, 3, time.Hour); !errors.Is(err, ErrCodeAttempts) {
		t.Fatalf("right code while locked out: %v", err)
	}
	// Another chat is unaffected, and the lockout ends with its window.
	if _, err := bots.RedeemLinkCode(ctx, "bale", "2", []byte("x"), now, 3, time.Hour); !errors.Is(err, ErrCodeInvalid) {
		t.Fatalf("other chat: %v", err)
	}
	if id, err := bots.RedeemLinkCode(ctx, "bale", "1", []byte("right"), now.Add(time.Hour), 3, time.Hour); err != nil || id != user.ID {
		t.Fatalf("after the window = %q, %v", id, err)
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

func TestLinkedChatsAndTrackFileIDs(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	user, _ := NewUsers(pool).Create(ctx, "bot@example.com", "hash")
	other, _ := NewUsers(pool).Create(ctx, "other@example.com", "hash")
	bots := NewBots(pool)
	tracks := NewTracks(pool)
	now := time.Now()

	link := func(userID, provider, chatID string, at time.Time) {
		t.Helper()
		hash := []byte(provider + chatID)
		if err := bots.CreateLinkCode(ctx, userID, hash, at.Add(time.Hour)); err != nil {
			t.Fatal(err)
		}
		if _, err := bots.RedeemLinkCode(ctx, provider, chatID, hash, at, 5, time.Hour); err != nil {
			t.Fatal(err)
		}
	}
	link(user.ID, "bale", "1", now)
	link(user.ID, "telegram", "2", now.Add(-48*time.Hour))
	link(other.ID, "bale", "3", now)

	chats, err := bots.LinkedChats(ctx, user.ID, "bale", now.Add(-time.Hour))
	if err != nil || len(chats) != 1 || chats[0] != "1" {
		t.Fatalf("bale chats = %v, %v", chats, err)
	}
	if chats, _ := bots.LinkedChats(ctx, user.ID, "telegram", now.Add(-time.Hour)); len(chats) != 0 {
		t.Fatalf("expired telegram link listed: %v", chats)
	}
	providers, err := bots.LinkedProviders(ctx, user.ID, now.Add(-72*time.Hour))
	if err != nil || len(providers) != 2 || providers[0] != "bale" || providers[1] != "telegram" {
		t.Fatalf("providers = %v, %v", providers, err)
	}

	track, err := tracks.Create(ctx, user.ID, NewTrack{Title: "t", FileName: "t.mp3", ContentType: "audio/mpeg", SizeBytes: 1})
	if err != nil {
		t.Fatal(err)
	}
	if id, err := bots.TrackFileID(ctx, "bale", track.ID); err != nil || id != "" {
		t.Fatalf("unsent track file ID = %q, %v", id, err)
	}
	bots.SaveTrackFileID(ctx, "bale", track.ID, "first")
	bots.SaveTrackFileID(ctx, "bale", track.ID, "second")
	if id, _ := bots.TrackFileID(ctx, "bale", track.ID); id != "second" {
		t.Fatalf("file ID = %q", id)
	}
	if err := tracks.Delete(ctx, user.ID, track.ID); err != nil {
		t.Fatal(err)
	}
	if id, _ := bots.TrackFileID(ctx, "bale", track.ID); id != "" {
		t.Fatalf("file ID survived its track: %q", id)
	}
}
