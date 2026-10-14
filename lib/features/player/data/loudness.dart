import 'dart:math';

import 'package:nafir/features/library/data/track.dart';

/// How tracks are evened out in loudness (#253).
enum LoudnessMode {
  /// Every file plays exactly as stored.
  off,

  /// Each track to the same loudness.
  track,

  /// Each album as a whole, keeping its quiet and loud songs as mastered;
  /// tracks without album values fall back to [track].
  album,
}

/// The volume (0 to 1) that brings [track] to the ReplayGain reference
/// loudness under [mode]. The files are never changed, only their volume:
/// - the gain is capped by the track's peak, so normalizing never clips;
/// - players can only turn audio down, so a quiet track (positive gain)
///   plays as stored rather than louder;
/// - a track whose tags carry no ReplayGain plays as stored.
double normalizationGain(Track track, LoudnessMode mode) {
  final replayGain = track.replayGain;
  if (mode == LoudnessMode.off || replayGain == null) return 1;
  final useAlbum = mode == LoudnessMode.album && replayGain.albumGainDb != null;
  final gainDb = useAlbum ? replayGain.albumGainDb : replayGain.trackGainDb;
  if (gainDb == null || !gainDb.isFinite) return 1;
  final peak = useAlbum
      ? (replayGain.albumPeak ?? replayGain.trackPeak)
      : replayGain.trackPeak;
  var gain = pow(10, gainDb / 20).toDouble();
  if (peak != null && peak > 0 && peak.isFinite) gain = min(gain, 1 / peak);
  return gain.clamp(0.0, 1.0);
}
