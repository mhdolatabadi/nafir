import 'dart:math';

import 'package:nafir/features/library/data/track.dart';

enum QueueRepeat { off, all, one }

/// The order tracks play in. Pure logic with an injectable [Random], so its
/// behaviour is deterministic in tests.
class PlayQueue {
  PlayQueue(List<Track> tracks, {int start = 0, Random? random})
      : assert(tracks.isNotEmpty),
        _tracks = List.unmodifiable(tracks),
        _random = random ?? Random(),
        _order = List.generate(tracks.length, (i) => i),
        _position = start.clamp(0, tracks.length - 1);

  final List<Track> _tracks;
  final Random _random;

  /// Indexes into [_tracks] in play order; [_position] points into it.
  List<int> _order;
  int _position;
  bool _shuffled = false;
  QueueRepeat repeat = QueueRepeat.off;

  Track get current => _tracks[_order[_position]];
  bool get shuffled => _shuffled;

  /// Tracks in the order they will play.
  List<Track> get upcoming =>
      [for (final i in _order.skip(_position + 1)) _tracks[i]];

  /// Shuffles everything except the current track, which keeps playing
  /// and becomes the first of the new order. Turning shuffle off returns to
  /// library order at the current track.
  set shuffled(bool value) {
    if (value == _shuffled) return;
    final currentIndex = _order[_position];
    if (value) {
      final rest = [
        for (var i = 0; i < _tracks.length; i++)
          if (i != currentIndex) i
      ]..shuffle(_random);
      _order = [currentIndex, ...rest];
      _position = 0;
    } else {
      _order = List.generate(_tracks.length, (i) => i);
      _position = currentIndex;
    }
    _shuffled = value;
  }

  /// The track after the current one, or null at the end of the queue.
  ///
  /// [auto] is true when the current track finished by itself: only then
  /// does [QueueRepeat.one] replay it. A user pressing "next" always moves on.
  Track? next({bool auto = false}) {
    if (auto && repeat == QueueRepeat.one) return current;
    if (_position < _order.length - 1) {
      _position++;
      return current;
    }
    if (repeat == QueueRepeat.off) return null;
    _position = 0;
    return current;
  }

  /// The track before the current one; at the start it wraps only when
  /// repeating the whole queue, otherwise it stays on the first track.
  Track previous() {
    if (_position > 0) {
      _position--;
    } else if (repeat == QueueRepeat.all) {
      _position = _order.length - 1;
    }
    return current;
  }
}
