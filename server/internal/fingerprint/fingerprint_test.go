package fingerprint

import (
	"context"
	"encoding/binary"
	"math"
	"math/rand"
	"os"
	"path/filepath"
	"testing"
	"time"
)

const sampleRate = 22050

// song generates a synthetic tune: seed picks a sequence of notes with
// harmonics, a quarter second each, over a simple beat.
func song(seed int64, seconds float64) []float64 {
	rng := rand.New(rand.NewSource(seed))
	samples := make([]float64, int(seconds*sampleRate))
	noteLen := sampleRate / 4
	var freq float64
	for i := range samples {
		if i%noteLen == 0 {
			freq = 220 * math.Pow(2, float64(rng.Intn(24))/12)
		}
		t := float64(i) / sampleRate
		envelope := math.Exp(-3 * float64(i%noteLen) / float64(noteLen))
		v := 0.5*math.Sin(2*math.Pi*freq*t) + 0.25*math.Sin(4*math.Pi*freq*t) + 0.12*math.Sin(6*math.Pi*freq*t)
		beat := 0.0
		if i%(sampleRate/2) < sampleRate/40 {
			beat = 0.3 * math.Sin(2*math.Pi*60*t)
		}
		samples[i] = 0.6*envelope*v + beat
	}
	return samples
}

// withNoise adds white noise at the given signal-to-noise ratio, like a
// phone hearing music across a room.
func withNoise(samples []float64, snrDB float64, seed int64) []float64 {
	rng := rand.New(rand.NewSource(seed))
	var power float64
	for _, s := range samples {
		power += s * s
	}
	power /= float64(len(samples))
	sigma := math.Sqrt(power / math.Pow(10, snrDB/10))
	out := make([]float64, len(samples))
	for i, s := range samples {
		out[i] = 0.8 * (s + rng.NormFloat64()*sigma)
	}
	return out
}

func writeWAV(t *testing.T, samples []float64) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "audio.wav")
	data := make([]byte, 44+2*len(samples))
	copy(data, "RIFF")
	binary.LittleEndian.PutUint32(data[4:], uint32(36+2*len(samples)))
	copy(data[8:], "WAVEfmt ")
	binary.LittleEndian.PutUint32(data[16:], 16)
	binary.LittleEndian.PutUint16(data[20:], 1)
	binary.LittleEndian.PutUint16(data[22:], 1)
	binary.LittleEndian.PutUint32(data[24:], sampleRate)
	binary.LittleEndian.PutUint32(data[28:], sampleRate*2)
	binary.LittleEndian.PutUint16(data[32:], 2)
	binary.LittleEndian.PutUint16(data[34:], 16)
	copy(data[36:], "data")
	binary.LittleEndian.PutUint32(data[40:], uint32(2*len(samples)))
	for i, s := range samples {
		v := int16(math.Max(-1, math.Min(1, s)) * 32767)
		binary.LittleEndian.PutUint16(data[44+2*i:], uint16(v))
	}
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func calculator(t *testing.T) Calculator {
	t.Helper()
	c := Calculator{MaxLength: 10 * time.Minute}
	if !c.Available() {
		t.Skip("fpcalc is not installed")
	}
	return c
}

func TestMatchesGeneratedAudio(t *testing.T) {
	c := calculator(t)
	ctx := context.Background()
	fingerprint := func(samples []float64) []uint32 {
		t.Helper()
		fp, err := c.File(ctx, writeWAV(t, samples))
		if err != nil {
			t.Fatal(err)
		}
		return fp.Points
	}
	track := song(1, 90)
	other := fingerprint(song(2, 90))
	full := fingerprint(track)

	start := int(31.3 * sampleRate)
	clip := track[start : start+10*sampleRate]
	cases := []struct {
		name    string
		snippet []float64
		match   bool
	}{
		{"clean", clip, true},
		{"noisy", withNoise(clip, 6, 7), true},
		{"very noisy", withNoise(clip, 0, 8), true},
		{"another song", song(3, 10), false},
		{"silence with noise", withNoise(make([]float64, 10*sampleRate), -100, 9), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			snippet := fingerprint(tc.snippet)
			got := Compare(snippet, full)
			against := Compare(snippet, other)
			t.Logf("confidence %.3f at %v; other song %.3f", got.Confidence, got.Offset, against.Confidence)
			if against.Confidence >= MinConfidence {
				t.Fatalf("matched an unrelated song with %.3f", against.Confidence)
			}
			if !tc.match {
				if got.Confidence >= MinConfidence {
					t.Fatalf("matched with %.3f", got.Confidence)
				}
				return
			}
			if got.Confidence < MinConfidence {
				t.Fatalf("no match: %.3f", got.Confidence)
			}
			if diff := got.Offset - 31300*time.Millisecond; diff < -time.Second || diff > time.Second {
				t.Fatalf("aligned at %v, want about 31.3s", got.Offset)
			}
		})
	}
}

func TestFileRejectsNonAudio(t *testing.T) {
	c := calculator(t)
	path := filepath.Join(t.TempDir(), "not-audio.mp3")
	_ = os.WriteFile(path, []byte("this is not audio at all"), 0o600)
	if _, err := c.File(context.Background(), path); err == nil {
		t.Fatal("text was fingerprinted")
	}
	missing := Calculator{Path: filepath.Join(t.TempDir(), "no-fpcalc")}
	if missing.Available() {
		t.Fatal("a missing binary is available")
	}
}

func TestCompareSynthetic(t *testing.T) {
	rng := rand.New(rand.NewSource(1))
	track := make([]uint32, 1000)
	for i := range track {
		track[i] = rng.Uint32()
	}
	snippet := append([]uint32(nil), track[400:480]...)
	if s := Compare(snippet, track); s.Confidence != 1 || s.Offset != 400*ItemDuration {
		t.Fatalf("exact = %+v", s)
	}
	// Flip a fifth of the bits: still clearly the same.
	for i := range snippet {
		for b := 0; b < 32; b++ {
			if rng.Intn(5) == 0 {
				snippet[i] ^= 1 << b
			}
		}
	}
	if s := Compare(snippet, track); s.Confidence < 0.5 || s.Offset != 400*ItemDuration {
		t.Fatalf("noisy = %+v", s)
	}
	random := make([]uint32, 80)
	for i := range random {
		random[i] = rng.Uint32()
	}
	if s := Compare(random, track); s.Confidence >= MinConfidence {
		t.Fatalf("random = %+v", s)
	}
	// A snippet running past the end still lines up.
	tail := append(append([]uint32(nil), track[960:]...), random[:10]...)
	if s := Compare(tail, track); s.Offset != 960*ItemDuration || s.Confidence < MinConfidence {
		t.Fatalf("tail = %+v", s)
	}
	if s := Compare(nil, track); s.Confidence != 0 {
		t.Fatalf("empty = %+v", s)
	}
	if got := Decode(Encode(track[:5])); len(got) != 5 || got[4] != track[4] {
		t.Fatalf("round trip = %v", got)
	}
}
