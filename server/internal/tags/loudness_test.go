package tags

import (
	"bytes"
	"errors"
	"math"
	"testing"
)

func near(t *testing.T, name string, got *float64, want float64) {
	t.Helper()
	if got == nil || math.Abs(*got-want) > 1e-6 {
		t.Errorf("%s = %v, want %v", name, deref(got), want)
	}
}

func deref(v *float64) any {
	if v == nil {
		return nil
	}
	return *v
}

func TestReadLoudnessFromEachFormat(t *testing.T) {
	t.Run("mp3 TXXX", func(t *testing.T) {
		l, err := ReadLoudness(bytes.NewReader(fixture(t, "replaygain.mp3")), "a.mp3")
		if err != nil {
			t.Fatal(err)
		}
		near(t, "track gain", l.TrackGainDB, -7.25)
		near(t, "track peak", l.TrackPeak, 0.988525)
		near(t, "album gain", l.AlbumGainDB, -6.10)
		near(t, "album peak", l.AlbumPeak, 1.012)
	})
	t.Run("flac comment", func(t *testing.T) {
		l, err := ReadLoudness(bytes.NewReader(fixture(t, "replaygain.flac")), "a.FLAC")
		if err != nil {
			t.Fatal(err)
		}
		near(t, "track gain", l.TrackGainDB, 2.40)
		near(t, "track peak", l.TrackPeak, 0.5)
		if l.AlbumGainDB != nil || l.AlbumPeak != nil {
			t.Errorf("album values from nowhere: %+v", l)
		}
	})
	t.Run("ogg vorbis, lower-case keys", func(t *testing.T) {
		l, err := ReadLoudness(bytes.NewReader(fixture(t, "replaygain.ogg")), "a.ogg")
		if err != nil {
			t.Fatal(err)
		}
		near(t, "track gain", l.TrackGainDB, -1.5)
		near(t, "album gain", l.AlbumGainDB, -2)
	})
	t.Run("opus R128", func(t *testing.T) {
		l, err := ReadLoudness(bytes.NewReader(fixture(t, "replaygain.opus")), "a.opus")
		if err != nil {
			t.Fatal(err)
		}
		// -1280/256 = -5 dB re -23 LUFS = 0 dB re ReplayGain's -18 LUFS.
		near(t, "track gain", l.TrackGainDB, 0)
		near(t, "album gain", l.AlbumGainDB, 6)
	})
	t.Run("the existing FLAC fixture", func(t *testing.T) {
		l, err := ReadLoudness(bytes.NewReader(fixture(t, "tagged.flac")), "a.flac")
		if err != nil {
			t.Fatal(err)
		}
		near(t, "track gain", l.TrackGainDB, -3)
	})
}

func TestReadLoudnessWithoutTags(t *testing.T) {
	for _, name := range []string{"notag.mp3", "v24.mp3", "tagged.ogg", "tagged.opus"} {
		l, err := ReadLoudness(bytes.NewReader(fixture(t, name)), name)
		if err != nil || !l.Empty() {
			t.Errorf("%s: %+v, %v", name, l, err)
		}
	}
	if _, err := ReadLoudness(bytes.NewReader(fixture(t, "sample.m4a")), "sample.m4a"); !errors.Is(err, ErrUnsupported) {
		t.Errorf("m4a = %v, want ErrUnsupported", err)
	}
	if _, err := ReadLoudness(bytes.NewReader([]byte("not audio")), "x.flac"); !errors.Is(err, ErrMalformed) {
		t.Errorf("garbage = %v, want ErrMalformed", err)
	}
}

// ReadLoudness must not need the audio: a file cut right after its tags
// still reads.
func TestReadLoudnessReadsOnlyTheTags(t *testing.T) {
	data := fixture(t, "replaygain.mp3")
	size := 10 + (int(data[6])<<21 | int(data[7])<<14 | int(data[8])<<7 | int(data[9]))
	l, err := ReadLoudness(bytes.NewReader(data[:size]), "a.mp3")
	if err != nil {
		t.Fatal(err)
	}
	near(t, "track gain", l.TrackGainDB, -7.25)
}

func TestGainAndPeakParsing(t *testing.T) {
	for raw, want := range map[string]any{
		"-6.54 dB": -6.54, "+2.1dB": 2.1, " -0,5 DB ": -0.5, "3": 3.0,
		"": nil, "loud": nil, "-99 dB": nil, "45 dB": nil, "NaN dB": nil,
	} {
		if got := deref(parseGain(raw)); got != want {
			t.Errorf("parseGain(%q) = %v, want %v", raw, got, want)
		}
	}
	for raw, want := range map[string]any{"0.98": 0.98, "1.2": 1.2, "0": nil, "-1": nil, "x": nil, "11": nil} {
		if got := deref(parsePeak(raw)); got != want {
			t.Errorf("parsePeak(%q) = %v, want %v", raw, got, want)
		}
	}
	for raw, want := range map[string]any{"-1280": 0.0, "0": 5.0, "256": 6.0, "x": nil, "99999": nil} {
		if got := deref(parseR128(raw)); got != want {
			t.Errorf("parseR128(%q) = %v, want %v", raw, got, want)
		}
	}
}
