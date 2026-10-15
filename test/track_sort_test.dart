import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmo/features/library/application/track_sort.dart';
import 'package:rhythmo/features/library/data/track.dart';

Track track(String id, String title, [String? artist]) => Track(
    id: id,
    title: title,
    artist: artist,
    contentType: 'audio/mpeg',
    sizeBytes: 1);

void main() {
  final library = [
    track('1', 'zebra', 'Beta'),
    track('2', 'Apple'),
    track('3', 'banana', 'alpha'),
    track('4', 'apple', 'Beta'),
  ];

  List<String> ids(List<Track> tracks) => [for (final t in tracks) t.id];

  test('recent keeps the library order', () {
    expect(ids(sortTracks(library, TrackSort.recent)), ['1', '2', '3', '4']);
  });

  test('oldest reverses addition order without changing the library', () {
    expect(ids(sortTracks(library, TrackSort.oldest)), ['4', '3', '2', '1']);
    expect(ids(library), ['1', '2', '3', '4']);
  });

  test('title ignores case and keeps ties in library order', () {
    expect(ids(sortTracks(library, TrackSort.title)), ['2', '4', '3', '1']);
  });

  test('artist groups by artist, then title; unknown artists go last', () {
    expect(ids(sortTracks(library, TrackSort.artist)), ['3', '4', '1', '2']);
  });

  test('sorting does not change the list it was given', () {
    sortTracks(library, TrackSort.title);
    expect(ids(library), ['1', '2', '3', '4']);
  });
}
