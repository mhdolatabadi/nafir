package bot

import (
	"context"
	"errors"
	"testing"

	"github.com/mhdolatabadi/nafir/server/internal/store"
)

// newSendHarness links the listener's chat and stores one ready track.
func newSendHarness(t *testing.T) (*harness, *Sender, store.Track) {
	t.Helper()
	h := newHarness(t)
	h.provider.maxUpload = 50 << 20
	h.signIn()
	artist := "خواننده"
	track := store.Track{
		ID: "t1", OwnerID: "u1", Status: store.TrackReady, Title: "آهنگ", Artist: &artist,
		StorageKey: "users/u1/tracks/t1/song.mp3", ContentType: "audio/mpeg", SizeBytes: int64(len(song)),
	}
	h.tracks.tracks[track.ID] = track
	h.objects.objects[track.StorageKey] = song
	sender := NewSender(h.provider, h.store, h.tracks, h.objects, DefaultLinkLimits.SessionTTL, 2)
	sender.now = h.linker.now
	sender.run = func(work func()) { work() }
	return h, sender, track
}

func TestSendUploadsOnceThenReusesTheFileID(t *testing.T) {
	h, sender, track := newSendHarness(t)

	if err := sender.Send(context.Background(), "u1", track.ID); err != nil {
		t.Fatal(err)
	}
	if len(h.provider.sent) != 1 || h.provider.sent[0].FileID != "" ||
		h.provider.sent[0].Title != "آهنگ" || h.provider.sent[0].Performer != "خواننده" ||
		h.provider.sent[0].FileName != "song.mp3" {
		t.Fatalf("first send = %+v", h.provider.sent)
	}
	if string(h.provider.uploaded["file-1"]) != string(song) {
		t.Fatal("uploaded audio differs from the stored object")
	}

	if err := sender.Send(context.Background(), "u1", track.ID); err != nil {
		t.Fatal(err)
	}
	if len(h.provider.sent) != 2 || h.provider.sent[1].FileID != "file-1" || len(h.provider.uploaded) != 1 {
		t.Fatalf("second send re-uploaded: %+v", h.provider.sent)
	}
}

func TestSendFallsBackToUploadWhenTheFileIDIsStale(t *testing.T) {
	h, sender, track := newSendHarness(t)
	h.store.fileIDs["bale/t1"] = "gone"
	h.provider.staleIDs = map[string]bool{"gone": true}

	if err := sender.Send(context.Background(), "u1", track.ID); err != nil {
		t.Fatal(err)
	}
	if len(h.provider.uploaded) != 1 || h.store.fileIDs["bale/t1"] != "file-1" {
		t.Fatalf("stale file ID not replaced: %+v, %v", h.provider.sent, h.store.fileIDs)
	}
}

func TestSendIsRefusedUpFront(t *testing.T) {
	h, sender, track := newSendHarness(t)
	ctx := context.Background()

	if err := sender.Send(ctx, "someone-else", track.ID); !errors.Is(err, ErrTrackNotFound) {
		t.Fatalf("another user's track: %v", err)
	}
	pending := track
	pending.ID, pending.Status = "t2", store.TrackPending
	h.tracks.tracks[pending.ID] = pending
	if err := sender.Send(ctx, "u1", pending.ID); !errors.Is(err, ErrTrackNotFound) {
		t.Fatalf("pending track: %v", err)
	}

	h.provider.maxUpload = 10
	if err := sender.Send(ctx, "u1", track.ID); !errors.Is(err, ErrTrackTooLarge) {
		t.Fatalf("over the upload limit: %v", err)
	}

	h.text("/logout")
	if err := sender.Send(ctx, "u1", track.ID); !errors.Is(err, ErrNotLinked) {
		t.Fatalf("unlinked: %v", err)
	}
	if len(h.provider.sent) != 0 {
		t.Fatalf("refused sends reached the provider: %+v", h.provider.sent)
	}
}

func TestSendFailuresAreReportedInTheChat(t *testing.T) {
	h, sender, track := newSendHarness(t)

	h.provider.sendErr = errors.New("Forbidden: bot was blocked by the user")
	sender.Send(context.Background(), "u1", track.ID)
	if last := h.provider.last(); last != msgSendFailed("آهنگ") {
		t.Fatalf("failure reply = %q", last)
	}

	h.provider.sendErr = ErrFileTooLarge
	sender.Send(context.Background(), "u1", track.ID)
	if last := h.provider.last(); last != msgSendTooLarge("آهنگ", 50) {
		t.Fatalf("too-large reply = %q", last)
	}
}

func TestSendersRouteByProvider(t *testing.T) {
	_, sender, track := newSendHarness(t)
	senders := Senders{"bale": sender}
	if err := senders.Send(context.Background(), "telegram", "u1", track.ID); !errors.Is(err, ErrUnknownProvider) {
		t.Fatalf("unknown provider: %v", err)
	}
	if err := senders.Send(context.Background(), "bale", "u1", track.ID); err != nil {
		t.Fatal(err)
	}
}
