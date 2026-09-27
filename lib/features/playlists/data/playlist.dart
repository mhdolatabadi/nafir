import 'package:nafir/features/library/data/track.dart';

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.trackCount,
    required this.tracks,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'] as List<dynamic>?;
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      trackCount: json['trackCount'] as int,
      tracks: rawTracks
              ?.map((value) => Track.fromJson(value as Map<String, dynamic>))
              .toList() ??
          const [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  final String id;
  final String name;
  final int trackCount;
  final List<Track> tracks;
  final DateTime createdAt;
  final DateTime updatedAt;
}
