package bot

import (
	"bytes"
	"context"
	"crypto/subtle"
	"errors"
	"fmt"
	"io"
	"sync"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/store"
)

// memStore is an in-memory store.Bots with the same rules.
type memStore struct {
	mu      sync.Mutex
	chats   map[string]*store.BotChat
	codes   []*memCode
	updates map[string]bool
	imports map[string]*store.BotImport
	nextID  int
}

type memCode struct {
	store.LoginCode
	attempts  int
	used      bool
	createdAt time.Time
}

func newMemStore() *memStore {
	return &memStore{chats: map[string]*store.BotChat{}, updates: map[string]bool{}, imports: map[string]*store.BotImport{}}
}

func (m *memStore) chat(provider, chatID string) *store.BotChat {
	key := provider + "/" + chatID
	c, ok := m.chats[key]
	if !ok {
		c = &store.BotChat{Provider: provider, ChatID: chatID, State: store.ChatIdle}
		m.chats[key] = c
	}
	return c
}

func (m *memStore) Chat(_ context.Context, provider, chatID string) (store.BotChat, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return *m.chat(provider, chatID), nil
}

func (m *memStore) SetState(_ context.Context, provider, chatID string, state store.ChatState) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.chat(provider, chatID).State = state
	return nil
}

func (m *memStore) SignOut(_ context.Context, provider, chatID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	c := m.chat(provider, chatID)
	c.UserID, c.SignedInAt, c.State = nil, nil, store.ChatIdle
	return nil
}

func (m *memStore) CodesSince(_ context.Context, provider, chatID, email string, since time.Time) (int, int, *time.Time, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var forChat, forEmail int
	var last *time.Time
	for _, c := range m.codes {
		sameChat := c.Provider == provider && c.ChatID == chatID
		if sameChat && !c.createdAt.Before(since) {
			forChat++
		}
		if c.Email == email && !c.createdAt.Before(since) {
			forEmail++
		}
		if sameChat && (last == nil || c.createdAt.After(*last)) {
			at := c.createdAt
			last = &at
		}
	}
	return forChat, forEmail, last, nil
}

func (m *memStore) AddCode(_ context.Context, code store.LoginCode) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, c := range m.codes {
		if c.Provider == code.Provider && c.ChatID == code.ChatID {
			c.used = true
		}
	}
	m.codes = append(m.codes, &memCode{LoginCode: code, createdAt: clock})
	m.chat(code.Provider, code.ChatID).State = store.ChatAwaitingCode
	return nil
}

func (m *memStore) VerifyCode(_ context.Context, provider, chatID string, hash []byte, now time.Time, maxAttempts int) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var current *memCode
	for _, c := range m.codes {
		if c.Provider == provider && c.ChatID == chatID && !c.used && c.ExpiresAt.After(now) {
			current = c
		}
	}
	if current == nil {
		return "", store.ErrCodeInvalid
	}
	if current.attempts >= maxAttempts {
		return "", store.ErrCodeAttempts
	}
	if subtle.ConstantTimeCompare(current.CodeHash, hash) != 1 || current.UserID == nil {
		current.attempts++
		return "", store.ErrCodeInvalid
	}
	current.used = true
	c := m.chat(provider, chatID)
	c.UserID, c.SignedInAt, c.State = current.UserID, &now, store.ChatIdle
	return *current.UserID, nil
}

func (m *memStore) FirstDelivery(_ context.Context, provider, updateID string) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	key := provider + "/" + updateID
	if m.updates[key] {
		return false, nil
	}
	m.updates[key] = true
	return true, nil
}

func (m *memStore) AddImport(_ context.Context, i store.BotImport) (store.BotImport, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, existing := range m.imports {
		if existing.Provider == i.Provider && existing.ChatID == i.ChatID && existing.MessageID == i.MessageID {
			return store.BotImport{}, store.ErrDuplicateImport
		}
	}
	m.nextID++
	i.ID = fmt.Sprint("import-", m.nextID)
	i.State = store.ImportQueued
	m.imports[i.ID] = &i
	return i, nil
}

func (m *memStore) StartImport(_ context.Context, id string, staleBefore time.Time) (store.BotImport, bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	i, ok := m.imports[id]
	if !ok || (i.State != store.ImportQueued && !(i.State == store.ImportDownloading && staleBefore.After(clock))) {
		return store.BotImport{}, false, nil
	}
	i.State = store.ImportDownloading
	i.Attempts++
	return *i, true, nil
}

func (m *memStore) FinishImport(_ context.Context, id string, trackID, reason *string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	i := m.imports[id]
	i.State, i.TrackID, i.Error = store.ImportDone, trackID, reason
	if trackID == nil {
		i.State = store.ImportFailed
	}
	return nil
}

func (m *memStore) RequeueImport(_ context.Context, id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.imports[id].State = store.ImportQueued
	return nil
}

func (m *memStore) UnfinishedImports(_ context.Context, _ int) ([]store.BotImport, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var out []store.BotImport
	for _, i := range m.imports {
		if i.State == store.ImportQueued || i.State == store.ImportDownloading {
			out = append(out, *i)
		}
	}
	return out, nil
}

// clock is the fake current time shared by memStore and Auth in tests.
var clock = time.Date(2026, 9, 29, 12, 0, 0, 0, time.UTC)

type fakeUsers map[string]store.User

func (f fakeUsers) ByEmail(_ context.Context, email string) (store.User, string, error) {
	for _, u := range f {
		if u.Email == email {
			return u, "hash", nil
		}
	}
	return store.User{}, "", store.ErrNotFound
}

func (f fakeUsers) ByID(_ context.Context, id string) (store.User, error) {
	u, ok := f[id]
	if !ok {
		return store.User{}, store.ErrNotFound
	}
	return u, nil
}

type sentMail struct{ to, subject, body string }

type fakeMailer struct {
	mu   sync.Mutex
	sent []sentMail
	err  error
}

func (f *fakeMailer) Send(to, subject, body string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return f.err
	}
	f.sent = append(f.sent, sentMail{to, subject, body})
	return nil
}

type fakeProvider struct {
	mu       sync.Mutex
	messages []string
	files    map[string][]byte
	openErr  error
	maxBytes int64
}

func (p *fakeProvider) Name() string { return "bale" }

func (p *fakeProvider) Send(_ context.Context, _ string, text string) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.messages = append(p.messages, text)
	return nil
}

func (p *fakeProvider) Open(_ context.Context, fileID string) (io.ReadCloser, int64, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.openErr != nil {
		return nil, 0, p.openErr
	}
	data, ok := p.files[fileID]
	if !ok {
		return nil, 0, errors.New("no such file")
	}
	return io.NopCloser(bytes.NewReader(data)), int64(len(data)), nil
}

func (p *fakeProvider) MaxDownloadBytes() int64 { return p.maxBytes }

func (p *fakeProvider) last() string {
	p.mu.Lock()
	defer p.mu.Unlock()
	if len(p.messages) == 0 {
		return ""
	}
	return p.messages[len(p.messages)-1]
}

type fakeTracks struct {
	mu       sync.Mutex
	tracks   map[string]store.Track
	next     int
	quotaErr error
}

func (f *fakeTracks) ReservePending(_ context.Context, ownerID string, t store.NewTrack, _ int64, _ int) (store.Track, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.quotaErr != nil {
		return store.Track{}, f.quotaErr
	}
	f.next++
	id := fmt.Sprint("track-", f.next)
	track := store.Track{
		ID: id, OwnerID: ownerID, Status: store.TrackPending, Title: t.Title, Artist: t.Artist,
		StorageKey: store.StorageKey(ownerID, id, t.FileName), ContentType: t.ContentType, SizeBytes: t.SizeBytes,
	}
	f.tracks[id] = track
	return track, nil
}

func (f *fakeTracks) MarkReady(_ context.Context, ownerID, trackID string) (store.Track, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	t := f.tracks[trackID]
	t.Status = store.TrackReady
	f.tracks[trackID] = t
	return t, nil
}

func (f *fakeTracks) Delete(_ context.Context, _, trackID string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	delete(f.tracks, trackID)
	return nil
}

type fakeObjects struct {
	mu      sync.Mutex
	objects map[string][]byte
	putErr  error
}

func (f *fakeObjects) Put(_ context.Context, key string, r io.Reader, size int64, _ string) error {
	if f.putErr != nil {
		return f.putErr
	}
	data, err := io.ReadAll(r)
	if err != nil {
		return err
	}
	if int64(len(data)) != size {
		return fmt.Errorf("read %d bytes, expected %d", len(data), size)
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	f.objects[key] = data
	return nil
}

func (f *fakeObjects) Remove(_ context.Context, key string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	delete(f.objects, key)
	return nil
}
