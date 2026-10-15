package httpapi

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/mhdolatabadi/rhythmo/server/internal/store"
)

func TestTrackJSONCarriesReplayGain(t *testing.T) {
	gain, peak := -7.25, 0.98
	tagged, _ := json.Marshal(toTrackResponse(store.Track{ID: "t1", FileName: "a.mp3",
		Loudness: store.Loudness{TrackGainDB: &gain, TrackPeak: &peak}}))
	if !strings.Contains(string(tagged), `"replayGain":{"trackGainDb":-7.25,"trackPeak":0.98,"albumGainDb":null,"albumPeak":null}`) {
		t.Fatalf("tagged track JSON = %s", tagged)
	}
	plain, _ := json.Marshal(toTrackResponse(store.Track{ID: "t2", FileName: "b.mp3"}))
	if !strings.Contains(string(plain), `"replayGain":null`) {
		t.Fatalf("untagged track JSON = %s", plain)
	}
}
