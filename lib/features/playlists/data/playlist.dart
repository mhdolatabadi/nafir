import 'package:nafir/features/library/data/track.dart';

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.trackCount,
    required this.tracks,
    required this.createdAt,
    required this.updatedAt,
    this.shareToken,
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
      shareToken: json['shareToken'] as String?,
    );
  }

  final String id;
  final String name;
  final int trackCount;
  final List<Track> tracks;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Set while the playlist is shared by link.
  final String? shareToken;
}

/// A playlist someone shared, as it looks to whoever opens its link.
class SharedPlaylist {
  const SharedPlaylist({
    required this.shareToken,
    required this.name,
    required this.owner,
    required this.isOwner,
    required this.tracks,
  });

  factory SharedPlaylist.fromJson(
          String shareToken, Map<String, dynamic> json) =>
      SharedPlaylist(
        shareToken: shareToken,
        name: json['name'] as String,
        owner: json['owner'] as String,
        isOwner: json['isOwner'] == true,
        tracks: [
          for (final track in json['tracks'] as List<dynamic>)
            Track.fromJson(track as Map<String, dynamic>,
                sharedVia: shareToken),
        ],
      );

  final String shareToken;
  final String name;

  /// The owner's email, masked, for example «m***@gmail.com».
  final String owner;
  final bool isOwner;

  /// Playable through the share link, not the owner's own library.
  final List<Track> tracks;
}

/// The web link that opens a shared playlist in Nafir.
Uri sharedPlaylistLink(Uri appOrigin, String shareToken) =>
    appOrigin.replace(path: '/', queryParameters: {'shared': shareToken});

/// Finds the share token in a pasted link or code, or returns null.
String? shareTokenFrom(String input) {
  final text = input.trim();
  final uri = Uri.tryParse(text);
  final token = uri?.queryParameters['shared'] ?? text;
  return RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(token) ? token : null;
}
