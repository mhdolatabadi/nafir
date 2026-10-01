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
    this.isPublic = false,
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
      isPublic: json['public'] == true,
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

  /// Whether the shared playlist is listed among the popular ones for
  /// everyone; otherwise only people with its link find it.
  final bool isPublic;
}

/// How many people like a shared playlist, and whether the viewer does.
class PlaylistLikes {
  const PlaylistLikes({required this.liked, required this.likeCount});

  factory PlaylistLikes.fromJson(Map<String, dynamic> json) => PlaylistLikes(
        liked: json['liked'] == true,
        likeCount: json['likeCount'] as int? ?? 0,
      );

  final bool liked;
  final int likeCount;

  /// The likes after the viewer likes or unlikes, before the server says so.
  PlaylistLikes toggled() => PlaylistLikes(
        liked: !liked,
        likeCount: liked ? (likeCount > 0 ? likeCount - 1 : 0) : likeCount + 1,
      );

  @override
  bool operator ==(Object other) =>
      other is PlaylistLikes &&
      other.liked == liked &&
      other.likeCount == likeCount;

  @override
  int get hashCode => Object.hash(liked, likeCount);
}

/// A public playlist as it is listed among the popular ones.
class PublicPlaylist {
  const PublicPlaylist({
    required this.shareToken,
    required this.name,
    required this.owner,
    required this.isOwner,
    required this.trackCount,
    required this.likes,
  });

  factory PublicPlaylist.fromJson(Map<String, dynamic> json) => PublicPlaylist(
        shareToken: json['shareToken'] as String,
        name: json['name'] as String,
        owner: json['owner'] as String,
        isOwner: json['isOwner'] == true,
        trackCount: json['trackCount'] as int? ?? 0,
        likes: PlaylistLikes.fromJson(json),
      );

  final String shareToken;
  final String name;

  /// The owner's email, masked.
  final String owner;
  final bool isOwner;
  final int trackCount;
  final PlaylistLikes likes;

  PublicPlaylist withLikes(PlaylistLikes likes) => PublicPlaylist(
        shareToken: shareToken,
        name: name,
        owner: owner,
        isOwner: isOwner,
        trackCount: trackCount,
        likes: likes,
      );
}

/// A playlist someone shared, as it looks to whoever opens its link.
class SharedPlaylist {
  const SharedPlaylist({
    required this.shareToken,
    required this.name,
    required this.owner,
    required this.isOwner,
    required this.tracks,
    this.isPublic = false,
    this.likes = const PlaylistLikes(liked: false, likeCount: 0),
  });

  factory SharedPlaylist.fromJson(
          String shareToken, Map<String, dynamic> json) =>
      SharedPlaylist(
        shareToken: shareToken,
        name: json['name'] as String,
        owner: json['owner'] as String,
        isOwner: json['isOwner'] == true,
        isPublic: json['public'] == true,
        likes: PlaylistLikes.fromJson(json),
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

  /// Whether it is listed among the popular playlists.
  final bool isPublic;
  final PlaylistLikes likes;

  SharedPlaylist withLikes(PlaylistLikes likes) => SharedPlaylist(
        shareToken: shareToken,
        name: name,
        owner: owner,
        isOwner: isOwner,
        tracks: tracks,
        isPublic: isPublic,
        likes: likes,
      );
}

/// The web link to a shared playlist. A public one has its own page that
/// anyone, and search engines, can open; a link-only one opens in the app.
Uri sharedPlaylistLink(Uri origin, String shareToken, {bool public = false}) =>
    public
        ? origin.replace(path: '/p/$shareToken', queryParameters: null)
        : origin
            .replace(path: '/app/', queryParameters: {'shared': shareToken});

/// Finds the share token in a pasted link or code, or returns null. It
/// reads app links (`/app/?shared=…`, and the older `/?shared=…`), public
/// pages (`/p/…`) and a bare token.
String? shareTokenFrom(String input) {
  final text = input.trim();
  final uri = Uri.tryParse(text);
  final segments = uri?.pathSegments ?? const <String>[];
  final token = uri?.queryParameters['shared'] ??
      (segments.length == 2 && segments.first == 'p' ? segments.last : text);
  return RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(token) ? token : null;
}
