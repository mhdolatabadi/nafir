import 'package:flutter/foundation.dart';
import 'package:nafir/features/player/application/player_controller.dart';

/// How one play of a track went: how long from asking to hearing it, and how
/// often it stopped to buffer afterwards.
class PlayRecord {
  PlayRecord(this.trackId, this.startedAt, {this.preloaded = false});

  final String trackId;
  final DateTime startedAt;

  /// Moved on to gaplessly from the track before, already buffered.
  final bool preloaded;

  /// Time to first audio; null until it plays, or when it never did.
  Duration? firstAudio;

  /// Times playback stopped to buffer after it had started.
  int stalls = 0;

  @override
  String toString() {
    final first = firstAudio == null
        ? 'never played'
        : 'first audio in ${firstAudio!.inMilliseconds} ms';
    return 'playback: $trackId ${preloaded ? '(preloaded) ' : ''}'
        '$first, $stalls stall${stalls == 1 ? '' : 's'}';
  }
}

/// Counts time-to-first-audio and stalls per track (#254). Debug builds print
/// each finished play, so a change to buffering can be measured.
class PlaybackMetrics {
  PlaybackMetrics({bool? log}) : log = log ?? kDebugMode;

  final bool log;

  /// The most recent plays, oldest first, the current one last.
  final List<PlayRecord> plays = [];
  static const _kept = 50;

  PlayerStatus? _last;

  PlayRecord? get current => plays.isEmpty ? null : plays.last;

  /// A new track was asked for.
  void started(String trackId, DateTime at, {bool preloaded = false}) {
    _finishCurrent();
    plays.add(PlayRecord(trackId, at, preloaded: preloaded));
    if (plays.length > _kept) plays.removeAt(0);
    _last = null;
    if (preloaded) current!.firstAudio = Duration.zero;
  }

  /// The player's status changed.
  void status(PlayerStatus status, DateTime at) {
    final play = current;
    if (play == null || status == _last) return;
    final previous = _last;
    _last = status;
    if (status == PlayerStatus.playing && play.firstAudio == null) {
      play.firstAudio = at.difference(play.startedAt);
    } else if (status == PlayerStatus.buffering &&
        previous == PlayerStatus.playing &&
        play.firstAudio != null) {
      play.stalls++;
    }
  }

  void _finishCurrent() {
    final play = current;
    if (play != null && log) debugPrint(play.toString());
  }
}
