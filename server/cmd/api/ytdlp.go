package main

import (
	"errors"
	"log/slog"
	"net/url"
	"os"
	"os/exec"
	"time"

	"github.com/mhdolatabadi/nafir/server/internal/linkimport"
)

// setupYTDLP turns on imports from YouTube and Instagram when yt-dlp is
// installed (the API image ships a pinned one). It returns nil without it.
func setupYTDLP() (*linkimport.YTDLP, error) {
	if os.Getenv("YTDLP_ENABLED") == "false" {
		return nil, nil
	}
	path := os.Getenv("YTDLP_PATH")
	if path == "" {
		path = "yt-dlp"
	}
	resolved, err := exec.LookPath(path)
	if err != nil {
		slog.Info("yt-dlp not found; YouTube and Instagram imports are off")
		return nil, nil
	}
	proxy := os.Getenv("YTDLP_PROXY_URL")
	if proxy != "" {
		u, err := url.Parse(proxy)
		if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https" && u.Scheme != "socks5" && u.Scheme != "socks5h") {
			// Never echo the value: it may hold proxy credentials.
			return nil, errors.New("YTDLP_PROXY_URL must be an http, https, socks5 or socks5h URL")
		}
	}
	maxDuration, err := positiveDurationEnv("YTDLP_MAX_DURATION", 30*time.Minute)
	if err != nil {
		return nil, err
	}
	maxConcurrent, err := positiveIntEnv("YTDLP_MAX_CONCURRENT", 2)
	if err != nil {
		return nil, err
	}
	jsRuntimes := os.Getenv("YTDLP_JS_RUNTIMES")
	if jsRuntimes == "" {
		jsRuntimes = "node"
	}
	return linkimport.NewYTDLP(linkimport.YTDLPConfig{
		Path: resolved, Proxy: proxy, JSRuntimes: jsRuntimes, TempDir: os.Getenv("YTDLP_TMPDIR"),
		MaxDuration: maxDuration, MaxConcurrent: maxConcurrent,
	}), nil
}
