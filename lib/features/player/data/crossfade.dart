import 'dart:math';

/// The overlap actually used for a track: the [setting], shortened so a
/// short track still plays mostly on its own. Both are in listening time,
/// so the result already accounts for [speed].
Duration effectiveCrossfade(
  Duration setting,
  Duration trackDuration, {
  double speed = 1,
}) {
  if (setting <= Duration.zero || trackDuration <= Duration.zero) {
    return Duration.zero;
  }
  final listening = trackDuration.inMilliseconds / speed;
  return Duration(
    milliseconds: min(setting.inMilliseconds, listening ~/ 3),
  );
}

/// Whether the next track should start fading in at [position]. [crossfade]
/// is in listening time, [position] and [duration] in track time.
bool shouldStartCrossfade({
  required Duration position,
  required Duration duration,
  required Duration crossfade,
  double speed = 1,
}) {
  if (crossfade <= Duration.zero) return false;
  final remaining = duration - position;
  return remaining.inMilliseconds <= crossfade.inMilliseconds * speed;
}

/// Equal-power gains for the outgoing and incoming track at [progress]
/// (0 to 1), so the overlap keeps a steady loudness instead of dipping in
/// the middle as a linear fade does.
(double out, double into) crossfadeGains(double progress) {
  final p = progress.clamp(0.0, 1.0);
  return (cos(p * pi / 2), sin(p * pi / 2));
}
