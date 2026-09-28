package httpapi

import (
	"net"
	"net/http"
	"strconv"
	"sync"
	"time"
)

const clientIPHeader = "X-Nafir-Client-IP"

type RateLimit struct {
	Requests int
	Window   time.Duration
}

type rateBucket struct {
	count int
	reset time.Time
}

// RateLimiter is a bounded in-memory fixed-window limiter. Limits are local to
// one API process; Nafir currently deploys one API replica.
type RateLimiter struct {
	mu         sync.Mutex
	limit      RateLimit
	maxEntries int
	entries    map[string]rateBucket
	now        func() time.Time
}

func NewRateLimiter(limit RateLimit, maxEntries int) *RateLimiter {
	return &RateLimiter{
		limit: limit, maxEntries: maxEntries,
		entries: make(map[string]rateBucket), now: time.Now,
	}
}

func (l *RateLimiter) Allow(key string) (bool, time.Duration) {
	if l == nil {
		return true, 0
	}
	now := l.now()
	l.mu.Lock()
	defer l.mu.Unlock()

	bucket, exists := l.entries[key]
	if !exists || !now.Before(bucket.reset) {
		if !exists && len(l.entries) >= l.maxEntries {
			for candidate, value := range l.entries {
				if !now.Before(value.reset) {
					delete(l.entries, candidate)
				}
			}
			if len(l.entries) >= l.maxEntries {
				return false, l.limit.Window
			}
		}
		l.entries[key] = rateBucket{count: 1, reset: now.Add(l.limit.Window)}
		return true, 0
	}
	if bucket.count >= l.limit.Requests {
		return false, bucket.reset.Sub(now)
	}
	bucket.count++
	l.entries[key] = bucket
	return true, 0
}

func enforceRateLimit(w http.ResponseWriter, limiter *RateLimiter, key string) bool {
	allowed, retryAfter := limiter.Allow(key)
	if allowed {
		return true
	}
	seconds := int64((retryAfter + time.Second - 1) / time.Second)
	if seconds < 1 {
		seconds = 1
	}
	w.Header().Set("Retry-After", strconv.FormatInt(seconds, 10))
	writeError(w, http.StatusTooManyRequests, "rate_limited")
	return false
}

// clientIP trusts only a private header overwritten by Nafir's Caddy config.
// RemoteAddr remains the safe fallback for local development and tests.
func clientIP(r *http.Request) string {
	if value := r.Header.Get(clientIPHeader); net.ParseIP(value) != nil {
		return value
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil && net.ParseIP(host) != nil {
		return host
	}
	return "unknown"
}
