import 'package:nafir/features/library/data/track.dart';

/// How the track list is ordered.
enum TrackSort {
  /// The order the library gives: most recently added first.
  recent('تازه‌ترین'),
  title('نام آهنگ'),
  artist('خواننده');

  const TrackSort(this.label);

  /// The Persian name shown in the sort menu.
  final String label;
}

/// Returns [tracks] in [sort] order. Titles and artists compare without
/// case; tracks without an artist go last; ties keep their library order.
List<Track> sortTracks(List<Track> tracks, TrackSort sort) {
  if (sort == TrackSort.recent) return tracks;
  String key(String? value) => value?.trim().toLowerCase() ?? '';
  final indexed = [for (var i = 0; i < tracks.length; i++) (i, tracks[i])];
  int byTitle((int, Track) a, (int, Track) b) =>
      key(a.$2.title).compareTo(key(b.$2.title));
  indexed.sort((a, b) {
    var order = 0;
    if (sort == TrackSort.artist) {
      final artistA = key(a.$2.artist), artistB = key(b.$2.artist);
      if (artistA.isEmpty != artistB.isEmpty) {
        return artistA.isEmpty ? 1 : -1;
      }
      order = artistA.compareTo(artistB);
    }
    if (order == 0) order = byTitle(a, b);
    return order != 0 ? order : a.$1.compareTo(b.$1);
  });
  return [for (final (_, track) in indexed) track];
}
