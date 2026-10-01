import 'package:nafir/features/library/data/track.dart';

/// Tracks that share an album or an artist.
class TrackGroup {
  const TrackGroup({
    required this.name,
    required this.tracks,
    this.artist,
    this.unknown = false,
  });

  /// The first spelling seen, or «نامشخص» for tracks without one.
  final String name;

  /// For an album, the artist of its first track.
  final String? artist;

  /// Whether this collects the tracks that have no album or artist.
  final bool unknown;
  final List<Track> tracks;
}

/// Name shown for tracks without an album or artist.
const unknownGroupName = 'نامشخص';

/// Groups [tracks] by album, in name order, with tracks without an album
/// last. Names match regardless of case and extra spaces.
List<TrackGroup> groupByAlbum(List<Track> tracks) =>
    _group(tracks, (track) => track.album, withArtist: true);

/// Groups [tracks] by artist, like [groupByAlbum].
List<TrackGroup> groupByArtist(List<Track> tracks) =>
    _group(tracks, (track) => track.artist);

List<TrackGroup> _group(
  List<Track> tracks,
  String? Function(Track track) nameOf, {
  bool withArtist = false,
}) {
  final names = <String, String>{};
  final members = <String, List<Track>>{};
  final unknown = <Track>[];
  for (final track in tracks) {
    final name = nameOf(track)?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name == null || name.isEmpty) {
      unknown.add(track);
      continue;
    }
    final key = name.toLowerCase();
    names.putIfAbsent(key, () => name);
    (members[key] ??= []).add(track);
  }
  final keys = names.keys.toList()..sort();
  String? artistOf(List<Track> group) {
    final artist = group.first.artist?.trim();
    return artist == null || artist.isEmpty ? null : artist;
  }

  return [
    for (final key in keys)
      TrackGroup(
        name: names[key]!,
        artist: withArtist ? artistOf(members[key]!) : null,
        tracks: members[key]!,
      ),
    if (unknown.isNotEmpty)
      TrackGroup(name: unknownGroupName, unknown: true, tracks: unknown),
  ];
}
