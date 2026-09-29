package bot

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/store"
)

var song = append([]byte("ID3\x04\x00\x00\x00\x00\x00\x00"), make([]byte, 90)...)

type harness struct {
	t        *testing.T
	store    *memStore
	users    fakeUsers
	mailer   *fakeMailer
	provider *fakeProvider
	tracks   *fakeTracks
	objects  *fakeObjects
	auth     *Auth
	importer *Importer
	service  *Service
	update   int
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	h := &harness{
		t:        t,
		store:    newMemStore(),
		users:    fakeUsers{"u1": {ID: "u1", Email: "listener@example.com"}},
		mailer:   &fakeMailer{},
		provider: &fakeProvider{files: map[string][]byte{"song": song}, maxBytes: 20 << 20},
		tracks:   &fakeTracks{tracks: map[string]store.Track{}},
		objects:  &fakeObjects{objects: map[string][]byte{}},
	}
	auth, err := NewAuth(h.store, h.users, h.mailer, make([]byte, 32), DefaultAuthLimits)
	if err != nil {
		t.Fatal(err)
	}
	auth.now = func() time.Time { return clock }
	h.auth = auth
	h.importer = NewImporter(h.store, h.tracks, h.objects, UploadPolicy{
		Enabled: true, MaxFileBytes: 200 << 20, MaxOwnerBytes: 5 << 30, MaxPending: 3,
	})
	h.importer.retryDelay = 0
	h.service = NewService(h.provider, h.store, auth, h.users, h.importer)
	h.service.imports = func(work func()) { work() }
	return h
}

func (h *harness) send(u Update) string {
	h.t.Helper()
	h.update++
	if u.ID == "" {
		u.ID = fmt.Sprint(h.update)
	}
	if u.ChatID == "" {
		u.ChatID = "42"
		u.Private = true
	}
	if u.MessageID == "" {
		u.MessageID = u.ID
	}
	if err := h.service.Handle(context.Background(), u); err != nil {
		h.t.Fatalf("Handle(%+v): %v", u, err)
	}
	return h.provider.last()
}

func (h *harness) text(text string) string {
	h.t.Helper()
	return h.send(Update{Text: text})
}

var codePattern = regexp.MustCompile(`\d{6}`)

// signIn completes the email login and returns the emailed code.
func (h *harness) signIn() {
	h.t.Helper()
	h.text("/start")
	h.text("listener@example.com")
	code := codePattern.FindString(h.mailer.sent[len(h.mailer.sent)-1].body)
	if reply := h.text(code); !strings.Contains(reply, "l***@example.com") {
		h.t.Fatalf("sign-in reply = %q", reply)
	}
}

func TestLoginWithEmailCodeThenImportAudio(t *testing.T) {
	h := newHarness(t)

	if reply := h.text("/start"); reply != msgWelcome {
		t.Fatalf("/start = %q", reply)
	}
	if reply := h.text("  Listener@Example.com "); reply != msgCodeSent {
		t.Fatalf("email reply = %q", reply)
	}
	if len(h.mailer.sent) != 1 || h.mailer.sent[0].to != "listener@example.com" {
		t.Fatalf("mail = %+v", h.mailer.sent)
	}
	code := codePattern.FindString(h.mailer.sent[0].body)
	if code == "" {
		t.Fatalf("no code in %q", h.mailer.sent[0].body)
	}

	if reply := h.text("000000"); reply != msgBadCode && code != "000000" {
		t.Fatalf("wrong code reply = %q", reply)
	}
	// Typed on a Persian keyboard.
	persian := strings.Map(func(r rune) rune { return r - '0' + '۰' }, code)
	if reply := h.text(persian); reply != msgSignedIn("l***@example.com") {
		t.Fatalf("right code reply = %q", reply)
	}
	if reply := h.text("/status"); reply != msgStatus("l***@example.com") {
		t.Fatalf("/status = %q", reply)
	}

	h.send(Update{File: &File{ID: "song", Name: "My Song.mp3", SizeBytes: int64(len(song)), Title: "آهنگ من", Performer: "خواننده"}})
	if last := h.provider.last(); last != msgImported("آهنگ من") {
		t.Fatalf("import reply = %q (all: %q)", last, h.provider.messages)
	}
	if len(h.tracks.tracks) != 1 {
		t.Fatalf("tracks = %+v", h.tracks.tracks)
	}
	for _, track := range h.tracks.tracks {
		if track.OwnerID != "u1" || track.Status != store.TrackReady || *track.Artist != "خواننده" {
			t.Fatalf("track = %+v", track)
		}
		if string(h.objects.objects[track.StorageKey]) != string(song) {
			t.Fatal("stored object differs from the download")
		}
	}

	if reply := h.text("/logout"); reply != msgSignedOut {
		t.Fatalf("/logout = %q", reply)
	}
	if reply := h.send(Update{File: &File{ID: "song", Name: "b.mp3", SizeBytes: 1}}); reply != msgNotSignedIn {
		t.Fatalf("file after logout = %q", reply)
	}
}

func TestRedeliveredUpdatesAndMessagesImportOnce(t *testing.T) {
	h := newHarness(t)
	h.signIn()
	file := &File{ID: "song", Name: "a.mp3", SizeBytes: int64(len(song))}

	h.send(Update{ID: "900", MessageID: "7", File: file})
	sent := len(h.provider.messages)
	h.send(Update{ID: "900", MessageID: "7", File: file})
	// A new update ID for the same message, as after a provider-side retry.
	h.send(Update{ID: "901", MessageID: "7", File: file})

	if len(h.provider.messages) != sent {
		t.Fatalf("duplicates were answered: %q", h.provider.messages[sent:])
	}
	if len(h.tracks.tracks) != 1 {
		t.Fatalf("imported %d tracks", len(h.tracks.tracks))
	}
}

func TestUnknownEmailGetsTheSameAnswerAndNoCodeWorks(t *testing.T) {
	h := newHarness(t)
	h.text("/login")
	if reply := h.text("nobody@example.com"); reply != msgCodeSent {
		t.Fatalf("unknown email reply = %q", reply)
	}
	if len(h.mailer.sent) != 0 {
		t.Fatalf("mail sent for an unknown email: %+v", h.mailer.sent)
	}
	for _, code := range []string{"123456", "000000"} {
		if reply := h.text(code); reply != msgBadCode {
			t.Fatalf("code for unknown email = %q", reply)
		}
	}
}

func TestLoginCodesAreThrottled(t *testing.T) {
	h := newHarness(t)
	h.text("/login")
	h.text("listener@example.com")

	h.text("/login")
	if reply := h.text("listener@example.com"); !strings.Contains(reply, "ثانیهٔ دیگر") {
		t.Fatalf("second request within cooldown = %q", reply)
	}

	for i := 0; i < 4; i++ {
		clock = clock.Add(2 * time.Minute)
		h.text("/login")
		h.text("listener@example.com")
	}
	clock = clock.Add(2 * time.Minute)
	h.text("/login")
	if reply := h.text("listener@example.com"); reply != msgThrottled {
		t.Fatalf("sixth code in an hour = %q", reply)
	}
	if len(h.mailer.sent) != 5 {
		t.Fatalf("sent %d codes", len(h.mailer.sent))
	}
}

func TestWrongCodesLockTheCode(t *testing.T) {
	h := newHarness(t)
	h.text("/login")
	h.text("listener@example.com")
	code := codePattern.FindString(h.mailer.sent[0].body)
	wrong := "111111"
	if code == wrong {
		wrong = "222222"
	}
	for i := 0; i < DefaultAuthLimits.MaxAttempts; i++ {
		h.text(wrong)
	}
	if reply := h.text(code); reply != msgBadCode {
		t.Fatalf("right code after too many attempts = %q", reply)
	}
}

func TestExpiredSessionSignsOut(t *testing.T) {
	h := newHarness(t)
	h.signIn()
	clock = clock.Add(DefaultAuthLimits.SessionTTL + time.Hour)
	if reply := h.text("/status"); reply != msgNotSignedIn {
		t.Fatalf("/status after session expiry = %q", reply)
	}
}

func TestRefusedFilesExplainWhy(t *testing.T) {
	h := newHarness(t)
	h.signIn()

	cases := []struct {
		name string
		file *File
		want string
	}{
		{"pdf", &File{ID: "doc", Name: "notes.pdf", MIMEType: "application/pdf", SizeBytes: 10}, ReasonUnsupported},
		{"over provider limit", &File{ID: "song", Name: "big.mp3", SizeBytes: 21 << 20}, ReasonTooLarge},
		{"not really mp3", &File{ID: "fake", Name: "fake.mp3", SizeBytes: 20}, ReasonInvalid},
	}
	h.provider.files["fake"] = []byte("<html>not audio</html>")
	for _, c := range cases {
		if reply := h.send(Update{File: c.file}); reply != h.service.refused(c.want) {
			t.Errorf("%s: reply = %q", c.name, reply)
		}
	}
	if len(h.tracks.tracks) != 0 || len(h.objects.objects) != 0 {
		t.Fatalf("refused files left tracks %v or objects %v", h.tracks.tracks, h.objects.objects)
	}

	h.tracks.quotaErr = store.ErrQuotaExceeded
	if reply := h.send(Update{File: &File{ID: "song", Name: "a.mp3", SizeBytes: 1}}); reply != h.service.refused(ReasonQuota) {
		t.Fatalf("quota reply = %q", reply)
	}
}

func TestAudioWithoutAFileNameUsesItsMIMEType(t *testing.T) {
	h := newHarness(t)
	h.signIn()
	h.send(Update{File: &File{ID: "song", MIMEType: "audio/mpeg", SizeBytes: int64(len(song))}})
	if last := h.provider.last(); last != msgImported("track") {
		t.Fatalf("reply = %q", last)
	}
}

func TestStorageFailuresAreRetriedThenCleanedUp(t *testing.T) {
	h := newHarness(t)
	h.signIn()
	h.objects.putErr = errors.New("minio down")

	h.send(Update{File: &File{ID: "song", Name: "a.mp3", SizeBytes: int64(len(song))}})

	if last := h.provider.last(); last != h.service.refused(ReasonFailed) {
		t.Fatalf("reply = %q", last)
	}
	if len(h.tracks.tracks) != 0 {
		t.Fatalf("failed import left a reservation: %v", h.tracks.tracks)
	}
	for _, job := range h.store.imports {
		if job.Attempts != h.importer.maxAttempts || job.State != store.ImportFailed {
			t.Fatalf("import = %+v", job)
		}
	}
}

func TestGroupChatsAreRefused(t *testing.T) {
	h := newHarness(t)
	if reply := h.send(Update{ChatID: "-100", Text: "/start"}); reply != msgPrivateOnly {
		t.Fatalf("group /start = %q", reply)
	}
	h.send(Update{ChatID: "-100", Text: "hello everyone"})
	if len(h.provider.messages) != 1 {
		t.Fatalf("replied to group chatter: %q", h.provider.messages)
	}
}

func TestResumeFinishesInterruptedImports(t *testing.T) {
	h := newHarness(t)
	h.signIn()
	job, err := h.importer.Queue(context.Background(), h.provider,
		Update{ChatID: "42", MessageID: "5", File: &File{ID: "song", Name: "a.mp3"}}, "u1")
	if err != nil {
		t.Fatal(err)
	}
	// It was mid-download when the process stopped.
	h.store.imports[job.ID].State = store.ImportDownloading
	h.importer.now = func() time.Time { return clock.Add(time.Second) }

	h.service.Resume(context.Background())
	if h.store.imports[job.ID].State != store.ImportDone {
		t.Fatalf("resumed import = %+v", h.store.imports[job.ID])
	}
}

func TestParseCommand(t *testing.T) {
	for text, want := range map[string]string{
		"/start": "start", "/Start@NafirBot": "start", "/login now": "login", "/": "",
	} {
		got, ok := parseCommand(text)
		if got != want || ok != (want != "") {
			t.Errorf("parseCommand(%q) = %q, %v", text, got, ok)
		}
	}
	if _, ok := parseCommand("hello"); ok {
		t.Error("plain text parsed as a command")
	}
}

func TestNormalizeCode(t *testing.T) {
	for input, want := range map[string]string{
		"123456": "123456", "۱۲۳ ۴۵۶": "123456", "١٢٣-٤٥٦": "123456", "12345": "", "12a456": "",
	} {
		got, ok := normalizeCode(input)
		if ok != (want != "") || (ok && got != want) {
			t.Errorf("normalizeCode(%q) = %q, %v", input, got, ok)
		}
	}
}
