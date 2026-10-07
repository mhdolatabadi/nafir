package fingerprint

import (
	"context"

	"github.com/mhdolatabadi/nafir/server/internal/store"
)

// MatchStore walks the fingerprinted tracks a user may play;
// *store.Fingerprints implements it.
type MatchStore interface {
	EachMatchable(ctx context.Context, userID string, fn func(store.Matchable) error) error
}

// Result is the best match for a snippet.
type Result struct {
	Match store.Matchable
	Score Score
}

// ownPreference is how much lower a track in the user's own library may
// score and still win: when they saved a copy of a playlist's song, the
// copy they own is the better answer.
const ownPreference = 0.03

// Identify finds the track userID may play that best matches snippet, if
// any scores at least MinConfidence. Only tracks the store hands out for
// userID are ever compared, so other people's private libraries stay out.
func Identify(ctx context.Context, tracks MatchStore, userID string, snippet []uint32) (Result, bool, error) {
	var best Result
	found := false
	err := tracks.EachMatchable(ctx, userID, func(m store.Matchable) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		score := Compare(snippet, Decode(m.Points))
		if score.Confidence < MinConfidence {
			return nil
		}
		own, bestOwn := m.Track.OwnerID == userID, best.Match.Track.OwnerID == userID
		margin := 0.0
		switch {
		case own && !bestOwn:
			margin = ownPreference
		case !own && bestOwn:
			margin = -ownPreference
		}
		if !found || score.Confidence+margin > best.Score.Confidence {
			m.Points = nil
			best, found = Result{Match: m, Score: score}, true
		}
		return nil
	})
	if err != nil {
		return Result{}, false, err
	}
	return best, found, nil
}
