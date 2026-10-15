import 'package:nafir/core/search_text.dart';
import 'package:nafir/features/library/data/track.dart';

/// Values already used in the library, offered while editing a track's
/// metadata so names stay consistent ("محمود کریمی", not a new spelling).
class MetadataSuggestions {
  const MetadataSuggestions({
    this.artists = const [],
    this.albums = const [],
    this.composers = const [],
    this.genres = const [],
  });

  /// Collects distinct values from [tracks], most used first. Artist and
  /// album artist share one pool because they name the same people.
  factory MetadataSuggestions.fromTracks(Iterable<Track> tracks) {
    final artists = _Counter();
    final albums = _Counter();
    final composers = _Counter();
    final genres = _Counter();
    for (final track in tracks) {
      artists
        ..add(track.artist)
        ..add(track.albumArtist);
      albums.add(track.album);
      composers.add(track.composer);
      genres.add(track.genre);
    }
    return MetadataSuggestions(
      artists: artists.ranked(),
      albums: albums.ranked(),
      composers: composers.ranked(),
      genres: genres.ranked(),
    );
  }

  static const empty = MetadataSuggestions();

  final List<String> artists;
  final List<String> albums;
  final List<String> composers;
  final List<String> genres;
}

/// Up to [limit] of [ranked] that match [query]: values starting with it
/// (or with a word starting with it) first, then values containing it, each
/// group keeping [ranked]'s order. An empty query or an exact match of the
/// whole value gives nothing to suggest.
List<String> matchSuggestions(List<String> ranked, String query,
    {int limit = 6}) {
  final q = normalizeForSearch(query);
  if (q.isEmpty) return const [];
  final prefix = <String>[];
  final contains = <String>[];
  for (final value in ranked) {
    final v = normalizeForSearch(value);
    if (v == q) continue;
    if (v.startsWith(q) || v.contains(' $q')) {
      prefix.add(value);
      if (prefix.length >= limit) break;
    } else if (v.contains(q)) {
      contains.add(value);
    }
  }
  return [...prefix, ...contains].take(limit).toList(growable: false);
}

class _Counter {
  final _counts = <String, int>{};

  /// The spelling seen most for each normalized key.
  final _spellings = <String, Map<String, int>>{};

  void add(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return;
    final key = normalizeForSearch(text);
    _counts[key] = (_counts[key] ?? 0) + 1;
    final spellings = _spellings.putIfAbsent(key, () => {});
    spellings[text] = (spellings[text] ?? 0) + 1;
  }

  List<String> ranked() {
    final keys = _counts.keys.toList()
      ..sort((a, b) {
        final byCount = _counts[b]!.compareTo(_counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return [
      for (final key in keys)
        _spellings[key]!
            .entries
            .reduce((a, b) => b.value > a.value ? b : a)
            .key,
    ];
  }
}
