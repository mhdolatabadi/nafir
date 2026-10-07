// Package fingerprint identifies songs from a short recording. Every ready
// track gets a Chromaprint acoustic fingerprint (computed with fpcalc from
// a temporary copy; the stored file is never changed), and a snippet's
// fingerprint is compared with those of the tracks its listener may play.
package fingerprint

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"math/bits"
	"os/exec"
	"strconv"
	"time"
)

var (
	// ErrNoAudio means fpcalc found no decodable audio, or too little.
	ErrNoAudio = errors.New("no usable audio")
	// ErrUnavailable means fpcalc is missing or failed to run.
	ErrUnavailable = errors.New("fingerprinting unavailable")
)

// ItemDuration is how much audio one fingerprint item stands for:
// Chromaprint's default hop of 1365 samples at 11025 Hz, a third of a frame.
const ItemDuration = 1365 * time.Second / 11025

// Fingerprint is Chromaprint's raw fingerprint: one 32-bit item per
// ItemDuration of audio.
type Fingerprint struct {
	Duration time.Duration
	Points   []uint32
}

// Calculator runs fpcalc.
type Calculator struct {
	// Path is the fpcalc binary; "fpcalc" on PATH when empty.
	Path string
	// MaxLength is how much audio is fingerprinted at most.
	MaxLength time.Duration
	// Timeout bounds one run.
	Timeout time.Duration
}

// Available reports whether fpcalc can be found.
func (c Calculator) Available() bool {
	_, err := exec.LookPath(c.path())
	return err == nil
}

func (c Calculator) path() string {
	if c.Path == "" {
		return "fpcalc"
	}
	return c.Path
}

// File fingerprints the audio file at path. Its contents never reach the
// logs: errors carry only fpcalc's exit status.
func (c Calculator) File(ctx context.Context, path string) (Fingerprint, error) {
	timeout := c.Timeout
	if timeout <= 0 {
		timeout = 2 * time.Minute
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	length := int(c.MaxLength / time.Second)
	if length <= 0 {
		length = 120
	}
	var stdout bytes.Buffer
	cmd := exec.CommandContext(ctx, c.path(), "-raw", "-json", "-length", strconv.Itoa(length), "--", path)
	cmd.Stdout = &stdout
	if err := cmd.Run(); err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) && ctx.Err() == nil {
			// fpcalc exits non-zero for files it can't decode.
			return Fingerprint{}, fmt.Errorf("%w: fpcalc exited with %d", ErrNoAudio, exitErr.ExitCode())
		}
		return Fingerprint{}, fmt.Errorf("%w: %v", ErrUnavailable, err)
	}
	var out struct {
		Duration    float64  `json:"duration"`
		Fingerprint []uint32 `json:"fingerprint"`
	}
	if err := json.Unmarshal(stdout.Bytes(), &out); err != nil {
		return Fingerprint{}, fmt.Errorf("%w: unreadable fpcalc output", ErrUnavailable)
	}
	if len(out.Fingerprint) == 0 {
		return Fingerprint{}, ErrNoAudio
	}
	return Fingerprint{
		Duration: time.Duration(out.Duration * float64(time.Second)),
		Points:   out.Fingerprint,
	}, nil
}

// Encode packs points for storage, four little-endian bytes each.
func Encode(points []uint32) []byte {
	out := make([]byte, 4*len(points))
	for i, p := range points {
		binary.LittleEndian.PutUint32(out[4*i:], p)
	}
	return out
}

// Decode unpacks Encode's bytes.
func Decode(data []byte) []uint32 {
	points := make([]uint32, len(data)/4)
	for i := range points {
		points[i] = binary.LittleEndian.Uint32(data[4*i:])
	}
	return points
}

// MinConfidence is the least Confidence that counts as a match. Unrelated
// audio scores near 0; the same recording, even through a phone's
// microphone in a noisy room, scores well above it.
const MinConfidence = 0.35

// Score compares a snippet with a track's fingerprint. Confidence is
// 1 - 2·(bit error rate) at the best alignment, from 0 (unrelated) to 1
// (identical); Offset is where in the track the snippet best lines up.
type Score struct {
	Confidence float64
	Offset     time.Duration
}

// minOverlap is the share of the snippet that must lie inside the track at
// an alignment, so a few items at the very end can't match by chance.
const minOverlap = 0.75

// Compare finds the alignment of snippet within track with the fewest
// differing bits.
func Compare(snippet, track []uint32) Score {
	n := len(snippet)
	if n == 0 || len(track) == 0 {
		return Score{}
	}
	need := int(float64(n) * minOverlap)
	if need < 1 {
		need = 1
	}
	if len(track) < need {
		return Score{}
	}
	best := Score{}
	bestRate := 1.0
	// offset is where snippet[0] falls in the track; it may hang over
	// either end by up to n - need items.
	for offset := need - n; offset <= len(track)-need; offset++ {
		start, end := max(0, -offset), min(n, len(track)-offset)
		if end-start < need {
			continue
		}
		differing := 0
		for i := start; i < end; i++ {
			differing += bits.OnesCount32(snippet[i] ^ track[i+offset])
		}
		rate := float64(differing) / float64(32*(end-start))
		if rate < bestRate {
			bestRate = rate
			best.Offset = time.Duration(offset) * ItemDuration
		}
	}
	best.Confidence = max(0, 1-2*bestRate)
	return best
}
