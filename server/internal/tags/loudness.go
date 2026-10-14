package tags

import (
	"bufio"
	"errors"
	"io"
	"math"
	"path"
	"strconv"
	"strings"
)

// Loudness is the ReplayGain a file's tags carry: gains in dB relative to the
// ReplayGain reference level (-18 LUFS) and sample peaks as linear amplitude
// (1 is full scale). Nil means the tag is absent or unusable.
type Loudness struct {
	TrackGainDB *float64
	TrackPeak   *float64
	AlbumGainDB *float64
	AlbumPeak   *float64
}

// Empty reports whether no value was found.
func (l Loudness) Empty() bool {
	return l.TrackGainDB == nil && l.TrackPeak == nil && l.AlbumGainDB == nil && l.AlbumPeak == nil
}

// ReadLoudness reads the ReplayGain tags of a file named like fileName. Only
// the tag header at the start of the file is read, never the audio. A
// format that carries no such tags is ErrUnsupported.
func ReadLoudness(r io.Reader, fileName string) (Loudness, error) {
	br := bufio.NewReader(r)
	switch strings.ToLower(path.Ext(fileName)) {
	case ".mp3":
		tag, err := readID3(br)
		if err != nil {
			return Loudness{}, err
		}
		return tag.loudness(), nil
	case ".flac":
		blocks, err := readFLACMetadata(br)
		if err != nil {
			return Loudness{}, err
		}
		return flacComment(blocks).loudness(false), nil
	case ".ogg", ".opus":
		headers, err := readOggHeaders(br)
		if errors.Is(err, ErrUnsupported) {
			return Loudness{}, err
		}
		if err != nil {
			return Loudness{}, err
		}
		return headers.comment.loudness(headers.opus), nil
	}
	return Loudness{}, ErrUnsupported
}

// r128Offset converts an Opus R128 gain (relative to -23 LUFS) to the
// ReplayGain reference (-18 LUFS).
const r128Offset = 5.0

func (vc vorbisComment) loudness(opus bool) Loudness {
	values := map[string]string{}
	for _, field := range vc.fields {
		key, value, ok := strings.Cut(field, "=")
		key = strings.ToUpper(strings.TrimSpace(key))
		if _, seen := values[key]; ok && !seen {
			values[key] = value
		}
	}
	l := Loudness{
		TrackGainDB: parseGain(values["REPLAYGAIN_TRACK_GAIN"]),
		TrackPeak:   parsePeak(values["REPLAYGAIN_TRACK_PEAK"]),
		AlbumGainDB: parseGain(values["REPLAYGAIN_ALBUM_GAIN"]),
		AlbumPeak:   parsePeak(values["REPLAYGAIN_ALBUM_PEAK"]),
	}
	if opus {
		// RFC 7845: Opus uses R128_*_GAIN, a Q7.8 integer in dB.
		if gain := parseR128(values["R128_TRACK_GAIN"]); gain != nil {
			l.TrackGainDB = gain
		}
		if gain := parseR128(values["R128_ALBUM_GAIN"]); gain != nil {
			l.AlbumGainDB = gain
		}
	}
	return l
}

func (t id3Tag) loudness() Loudness {
	values := map[string]string{}
	for _, frame := range t.frames {
		if string(frame[:4]) != "TXXX" {
			continue
		}
		body, ok := frameBody(t.major, frame)
		if !ok || len(body) < 2 {
			continue
		}
		encoding, rest := body[0], body[1:]
		end, width := terminator(encoding, rest)
		if end < 0 {
			continue
		}
		key := strings.ToUpper(strings.TrimSpace(decodeText(encoding, rest[:end])))
		if _, seen := values[key]; !seen {
			values[key] = decodeText(encoding, rest[end+width:])
		}
	}
	return Loudness{
		TrackGainDB: parseGain(values["REPLAYGAIN_TRACK_GAIN"]),
		TrackPeak:   parsePeak(values["REPLAYGAIN_TRACK_PEAK"]),
		AlbumGainDB: parseGain(values["REPLAYGAIN_ALBUM_GAIN"]),
		AlbumPeak:   parsePeak(values["REPLAYGAIN_ALBUM_PEAK"]),
	}
}

// parseGain reads values such as "-6.54 dB" or "+2.1dB"; anything outside a
// plausible range is ignored rather than trusted.
func parseGain(raw string) *float64 {
	value := strings.TrimSpace(strings.TrimRight(strings.TrimSpace(raw), "\x00"))
	if lower := strings.ToLower(value); strings.HasSuffix(lower, "db") {
		value = strings.TrimSpace(value[:len(value)-2])
	}
	gain, err := strconv.ParseFloat(strings.Replace(value, ",", ".", 1), 64)
	if err != nil || math.IsNaN(gain) || gain < -60 || gain > 30 {
		return nil
	}
	return &gain
}

func parsePeak(raw string) *float64 {
	value := strings.TrimSpace(strings.TrimRight(strings.TrimSpace(raw), "\x00"))
	peak, err := strconv.ParseFloat(strings.Replace(value, ",", ".", 1), 64)
	if err != nil || math.IsNaN(peak) || peak <= 0 || peak > 10 {
		return nil
	}
	return &peak
}

func parseR128(raw string) *float64 {
	q, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil || q < math.MinInt16 || q > math.MaxInt16 {
		return nil
	}
	gain := float64(q)/256 + r128Offset
	return &gain
}
