package linkimport

import (
	"context"
	"errors"
	"io"
	"os"

	"github.com/mhdolatabadi/nafir/server/internal/bot"
)

// ProviderName is the import source recorded for link imports.
const ProviderName = "link"

// Provider lets the bot import pipeline download from links: a file ID is
// the audio file's URL. It has no chat to talk to.
type Provider struct {
	fetcher  *Fetcher
	maxBytes int64
	// media downloads YouTube and Instagram imports; nil turns them off.
	media *YTDLP
}

var _ bot.Provider = (*Provider)(nil)

func NewProvider(fetcher *Fetcher, maxBytes int64) *Provider {
	return &Provider{fetcher: fetcher, maxBytes: maxBytes}
}

func (p *Provider) Name() string                               { return ProviderName }
func (p *Provider) Send(context.Context, string, string) error { return nil }
func (p *Provider) MaxDownloadBytes() int64                    { return p.maxBytes }
func (p *Provider) MaxUploadBytes() int64                      { return 0 }
func (p *Provider) SendAudio(context.Context, string, bot.OutgoingAudio) (string, error) {
	return "", errors.New("link imports cannot send audio")
}

// Open downloads the file at fileID. A server that doesn't say the length
// is spooled to a temporary file first, bounded by the size limit, which
// is removed when the body is closed.
func (p *Provider) Open(ctx context.Context, fileID string) (io.ReadCloser, int64, error) {
	if link, plan, ok := parseMediaFileID(fileID); ok {
		if p.media == nil {
			return nil, 0, ErrUnsupported
		}
		return p.media.Open(ctx, link, plan, p.maxBytes)
	}
	u, err := ParseURL(fileID)
	if err != nil {
		return nil, 0, err
	}
	resp, err := p.fetcher.get(ctx, u)
	if err != nil {
		return nil, 0, err
	}
	if resp.ContentLength > p.maxBytes {
		resp.Body.Close()
		return nil, 0, bot.ErrFileTooLarge
	}
	if resp.ContentLength > 0 {
		return resp.Body, resp.ContentLength, nil
	}
	defer resp.Body.Close()
	spool, err := os.CreateTemp("", "nafir-link-*")
	if err != nil {
		return nil, 0, err
	}
	discard := func() {
		spool.Close()
		os.Remove(spool.Name())
	}
	n, err := io.Copy(spool, io.LimitReader(resp.Body, p.maxBytes+1))
	if err != nil {
		discard()
		return nil, 0, err
	}
	if n > p.maxBytes {
		discard()
		return nil, 0, bot.ErrFileTooLarge
	}
	if _, err := spool.Seek(0, io.SeekStart); err != nil {
		discard()
		return nil, 0, err
	}
	return &tempFile{File: spool}, n, nil
}

// tempFile removes itself when closed.
type tempFile struct{ *os.File }

func (t *tempFile) Close() error {
	err := t.File.Close()
	os.Remove(t.Name())
	return err
}
