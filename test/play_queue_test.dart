import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/player/application/play_queue.dart';

final _tracks = [
  for (final id in ['a', 'b', 'c', 'd', 'e'])
    Track(id: id, title: id, contentType: 'audio/mpeg', sizeBytes: 1),
];

List<String> _ids(Iterable<Track> tracks) => [for (final t in tracks) t.id];

void main() {
  test('plays in library order from the chosen track', () {
    final queue = PlayQueue(_tracks, start: 2);
    expect(queue.current.id, 'c');
    expect(_ids(queue.upcoming), ['d', 'e']);
    expect(queue.next()?.id, 'd');
    expect(queue.next()?.id, 'e');
    expect(queue.next(), isNull, reason: 'the end without repeat');
  });

  test('previous steps back and stays on the first track', () {
    final queue = PlayQueue(_tracks, start: 1);
    expect(queue.previous().id, 'a');
    expect(queue.previous().id, 'a');
  });

  test('repeat all wraps in both directions', () {
    final queue = PlayQueue(_tracks, start: 4)..repeat = QueueRepeat.all;
    expect(queue.next()?.id, 'a');
    expect(queue.previous().id, 'e');
  });

  test('repeat one replays only when a track ends by itself', () {
    final queue = PlayQueue(_tracks)..repeat = QueueRepeat.one;
    expect(queue.next(auto: true)?.id, 'a');
    expect(queue.next()?.id, 'b', reason: 'the user skipping still moves on');
  });

  test('shuffle is deterministic for a seed and keeps the current track', () {
    PlayQueue shuffledWith(int seed) =>
        PlayQueue(_tracks, start: 2, random: Random(seed))..shuffled = true;

    final first = shuffledWith(7);
    final second = shuffledWith(7);
    expect(first.current.id, 'c');
    expect(_ids(first.upcoming), _ids(second.upcoming));
    expect(_ids(first.upcoming)..sort(), ['a', 'b', 'd', 'e']);
    expect(_ids(first.upcoming), isNot(['a', 'b', 'd', 'e']),
        reason: 'seed 7 produces a real reorder');
  });

  test('every track plays exactly once through a shuffled queue', () {
    final queue = PlayQueue(_tracks, random: Random(1))..shuffled = true;
    final played = [queue.current.id];
    for (var t = queue.next(); t != null; t = queue.next()) {
      played.add(t.id);
    }
    expect(played..sort(), ['a', 'b', 'c', 'd', 'e']);
  });

  test('turning shuffle off returns to library order at the current track', () {
    final queue = PlayQueue(_tracks, random: Random(3))..shuffled = true;
    queue.next();
    final now = queue.current.id;

    queue.shuffled = false;

    expect(queue.current.id, now);
    expect(_ids(queue.upcoming),
        _ids(_tracks.skipWhile((t) => t.id != now).skip(1)));
  });

  test('a single track queue', () {
    final queue = PlayQueue(_tracks.take(1).toList())..repeat = QueueRepeat.all;
    expect(queue.next()?.id, 'a');
    queue.shuffled = true;
    expect(queue.current.id, 'a');
  });
}
