package store

import "context"

// LoudnessJob is a ready track whose tags have not been read for ReplayGain.
type LoudnessJob struct {
	ID         string
	StorageKey string
	FileName   string
}

// PendingLoudness returns up to limit ready tracks not scanned yet, oldest
// first, so new uploads and the backfill of older tracks share one queue.
func (t *Tracks) PendingLoudness(ctx context.Context, limit int) ([]LoudnessJob, error) {
	rows, err := t.pool.Query(ctx, `
		SELECT id::text, storage_key, file_name FROM tracks
		WHERE status = 'ready' AND loudness_scanned_at IS NULL
		ORDER BY created_at, id
		LIMIT $1
	`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	jobs := []LoudnessJob{}
	for rows.Next() {
		var job LoudnessJob
		if err := rows.Scan(&job.ID, &job.StorageKey, &job.FileName); err != nil {
			return nil, err
		}
		jobs = append(jobs, job)
	}
	return jobs, rows.Err()
}

// SetLoudness records what scanning storageKey found; an empty Loudness
// marks the track as scanned with no ReplayGain. A track whose stored object
// changed meanwhile is left for the next scan. Tag rewrites keep ReplayGain,
// so they do not reset the scan.
func (t *Tracks) SetLoudness(ctx context.Context, trackID, storageKey string, l Loudness) error {
	tag, err := t.pool.Exec(ctx, `
		UPDATE tracks SET replaygain_track_gain_db = $3, replaygain_track_peak = $4,
			replaygain_album_gain_db = $5, replaygain_album_peak = $6, loudness_scanned_at = now()
		WHERE id::text = $1 AND storage_key = $2
	`, trackID, storageKey, l.TrackGainDB, l.TrackPeak, l.AlbumGainDB, l.AlbumPeak)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
