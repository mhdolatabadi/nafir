import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nafir/features/auth/data/auth_models.dart';
import 'package:nafir/features/bots/data/messenger_bot.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/link_import/data/link_import.dart';
import 'package:nafir/features/playlists/data/playlist.dart';
import 'package:nafir/features/upload/data/upload_models.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;

  /// Machine-readable error from the API body, for example `email_taken`.
  final String? code;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

abstract interface class AuthApi {
  Future<AuthSession> register(String email, String password);
  Future<AuthSession> login(String email, String password);
  Future<AuthUser> me(String token);

  /// Deletes the signed-in account and everything in it for good. The
  /// password is checked again; a wrong one fails with `invalid_password`.
  Future<void> deleteAccount(String token, String password);
}

/// A short-lived URL for playing one track.
class StreamLink {
  const StreamLink(this.url, this.expiresAt);

  final Uri url;
  final DateTime expiresAt;
}

class TrackLibrary {
  const TrackLibrary({
    required this.tracks,
    required this.usedBytes,
    required this.limitBytes,
    this.importsInProgress = 0,
  });

  final List<Track> tracks;
  final int usedBytes;
  final int limitBytes;

  /// Bot imports not in [tracks] yet.
  final int importsInProgress;
}

abstract interface class TracksApi {
  Future<TrackLibrary> listTracks(String token);
  Future<StreamLink> streamLink(String token, String trackId);
  Future<UploadTicket> createUpload(
      String token, String fileName, int sizeBytes);
  Future<Track> completeUpload(String token, String trackId);
  Future<Track> updateTrackMetadata(
    String token,
    String trackId, {
    String? fileName,
    required String title,
    String? artist,
    String? album,
    String? albumArtist,
    String? composer,
    String? genre,
    int? year,
    int? trackNumber,
    int? discNumber,
    String? comment,
  });
  Future<void> deleteTrack(String token, String trackId);

  /// A playback link for a track in a playlist shared with [shareToken].
  Future<StreamLink> sharedStreamLink(
      String? token, String shareToken, String trackId);

  /// A playback link for a track another member added to a collaborative
  /// playlist the user belongs to.
  Future<StreamLink> playlistStreamLink(
      String token, String playlistId, String trackId);
}

abstract interface class PlaylistsApi {
  Future<List<Playlist>> listPlaylists(String token);
  Future<Playlist> getPlaylist(String token, String playlistId);
  Future<Playlist> createPlaylist(String token, String name);
  Future<Playlist> renamePlaylist(String token, String playlistId, String name);
  Future<Playlist> replacePlaylistTracks(
      String token, String playlistId, List<String> trackIds);
  Future<void> deletePlaylist(String token, String playlistId);

  /// Shares the playlist by link and returns its share token; sharing again
  /// returns the same one. [public] lists it among the popular playlists
  /// (true) or keeps it to people with the link (false); null keeps what
  /// it was.
  Future<PlaylistShare> sharePlaylist(String token, String playlistId,
      {bool? public});

  /// Stops sharing; the old link stops working.
  Future<void> unsharePlaylist(String token, String playlistId);
  Future<SharedPlaylist> getSharedPlaylist(String? token, String shareToken);

  /// Copies a shared playlist and its tracks into the caller's account.
  Future<Playlist> saveSharedPlaylist(String token, String shareToken);

  /// Likes or unlikes a shared playlist; doing it twice is the same as once.
  Future<PlaylistLikes> setPlaylistLike(
      String token, String shareToken, bool liked);

  /// Public playlists, most liked first.
  Future<List<PublicPlaylist>> listPublicPlaylists(String? token);

  /// Makes a new collaboration link and returns its token; the old link
  /// stops working.
  Future<String> createCollabLink(String token, String playlistId);

  /// Turns the collaboration link off; members stay.
  Future<void> revokeCollabLink(String token, String playlistId);

  /// Joins the playlist with this collaboration link.
  Future<Playlist> joinPlaylist(String token, String collabToken);

  /// The owner takes a member out, with the tracks they added.
  Future<void> removePlaylistMember(
      String token, String playlistId, String memberId);

  /// Leaves a collaborative playlist, taking one's tracks out of it.
  Future<void> leavePlaylist(String token, String playlistId);
}

/// A playlist's share link as its owner set it.
typedef PlaylistShare = ({String shareToken, bool isPublic});

abstract interface class BotsApi {
  Future<List<MessengerBot>> listBots(String token);
  Future<BotLinkCode> createBotLinkCode(String token);

  /// Has the bot post a track into the account's linked chats.
  Future<void> sendTrackToBot(String token, String provider, String trackId);
}

class ApiClient
    implements AuthApi, TracksApi, PlaylistsApi, BotsApi, LinkImportsApi {
  ApiClient(this.baseUri, {http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  static const _timeout = Duration(seconds: 15);

  final Uri baseUri;
  final http.Client _httpClient;

  Future<void> checkHealth() async {
    final body = await _send('GET', '/api/v1/health');
    if (body['status'] != 'ok') {
      throw const ApiException('Server returned an invalid health response.');
    }
  }

  @override
  Future<AuthSession> register(String email, String password) async {
    final body = await _send('POST', '/api/v1/auth/register',
        body: {'email': email, 'password': password});
    return AuthSession.fromJson(body);
  }

  @override
  Future<AuthSession> login(String email, String password) async {
    final body = await _send('POST', '/api/v1/auth/login',
        body: {'email': email, 'password': password});
    return AuthSession.fromJson(body);
  }

  @override
  Future<AuthUser> me(String token) async {
    final body = await _send('GET', '/api/v1/me', token: token);
    return AuthUser.fromJson(body);
  }

  @override
  Future<void> deleteAccount(String token, String password) async {
    await _send('DELETE', '/api/v1/me',
        token: token, body: {'password': password}, expectBody: false);
  }

  @override
  Future<TrackLibrary> listTracks(String token) async {
    final body = await _send('GET', '/api/v1/tracks', token: token);
    final storage = body['storage'] as Map<String, dynamic>;
    return TrackLibrary(
      tracks: (body['tracks'] as List<dynamic>)
          .map((json) => Track.fromJson(json as Map<String, dynamic>))
          .toList(),
      usedBytes: (storage['usedBytes'] as num).toInt(),
      limitBytes: (storage['limitBytes'] as num).toInt(),
      importsInProgress: (body['importsInProgress'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<StreamLink> streamLink(String token, String trackId) async {
    final body =
        await _send('GET', '/api/v1/tracks/$trackId/stream', token: token);
    return StreamLink(
      Uri.parse(body['url'] as String),
      DateTime.parse(body['expiresAt'] as String),
    );
  }

  @override
  Future<UploadTicket> createUpload(
      String token, String fileName, int sizeBytes) async {
    final body = await _send('POST', '/api/v1/tracks/uploads',
        token: token, body: {'fileName': fileName, 'sizeBytes': sizeBytes});
    return UploadTicket.fromJson(body);
  }

  @override
  Future<Track> completeUpload(String token, String trackId) async {
    final body =
        await _send('POST', '/api/v1/tracks/$trackId/complete', token: token);
    return Track.fromJson(body);
  }

  @override
  Future<Track> updateTrackMetadata(
    String token,
    String trackId, {
    String? fileName,
    required String title,
    String? artist,
    String? album,
    String? albumArtist,
    String? composer,
    String? genre,
    int? year,
    int? trackNumber,
    int? discNumber,
    String? comment,
  }) async {
    final body =
        await _send('PATCH', '/api/v1/tracks/$trackId', token: token, body: {
      if (fileName != null) 'fileName': fileName,
      'title': title,
      'artist': artist,
      'album': album,
      'albumArtist': albumArtist,
      'composer': composer,
      'genre': genre,
      'year': year,
      'trackNumber': trackNumber,
      'discNumber': discNumber,
      'comment': comment,
    });
    return Track.fromJson(body);
  }

  @override
  Future<void> deleteTrack(String token, String trackId) async {
    await _send('DELETE', '/api/v1/tracks/$trackId',
        token: token, expectBody: false);
  }

  @override
  Future<List<Playlist>> listPlaylists(String token) async {
    final body = await _send('GET', '/api/v1/playlists', token: token);
    return (body['playlists'] as List<dynamic>)
        .map((json) => Playlist.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<PlaylistShare> sharePlaylist(String token, String playlistId,
      {bool? public}) async {
    final body = await _send(
        'POST', '/api/v1/playlists/${Uri.encodeComponent(playlistId)}/share',
        token: token, body: public == null ? null : {'public': public});
    return (
      shareToken: body['shareToken'] as String,
      isPublic: body['public'] == true,
    );
  }

  @override
  Future<PlaylistLikes> setPlaylistLike(
      String token, String shareToken, bool liked) async {
    final body = await _send(liked ? 'PUT' : 'DELETE',
        '/api/v1/shared-playlists/${Uri.encodeComponent(shareToken)}/like',
        token: token);
    return PlaylistLikes.fromJson(body);
  }

  @override
  Future<List<PublicPlaylist>> listPublicPlaylists(String? token) async {
    final body = await _send('GET', '/api/v1/public-playlists', token: token);
    return [
      for (final json in body['playlists'] as List<dynamic>)
        PublicPlaylist.fromJson(json as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> unsharePlaylist(String token, String playlistId) async {
    await _send(
        'DELETE', '/api/v1/playlists/${Uri.encodeComponent(playlistId)}/share',
        token: token, expectBody: false);
  }

  @override
  Future<SharedPlaylist> getSharedPlaylist(
      String? token, String shareToken) async {
    final body = await _send(
        'GET', '/api/v1/shared-playlists/${Uri.encodeComponent(shareToken)}',
        token: token);
    return SharedPlaylist.fromJson(shareToken, body);
  }

  @override
  Future<Playlist> saveSharedPlaylist(String token, String shareToken) async {
    final body = await _send('POST',
        '/api/v1/shared-playlists/${Uri.encodeComponent(shareToken)}/save',
        token: token);
    return Playlist.fromJson(body);
  }

  @override
  Future<StreamLink> sharedStreamLink(
      String? token, String shareToken, String trackId) async {
    final body = await _send(
        'GET',
        '/api/v1/shared-playlists/${Uri.encodeComponent(shareToken)}'
            '/tracks/${Uri.encodeComponent(trackId)}/stream',
        token: token);
    return StreamLink(Uri.parse(body['url'] as String),
        DateTime.parse(body['expiresAt'] as String));
  }

  @override
  Future<StreamLink> playlistStreamLink(
      String token, String playlistId, String trackId) async {
    final body = await _send(
        'GET',
        '/api/v1/playlists/${Uri.encodeComponent(playlistId)}'
            '/tracks/${Uri.encodeComponent(trackId)}/stream',
        token: token);
    return StreamLink(Uri.parse(body['url'] as String),
        DateTime.parse(body['expiresAt'] as String));
  }

  @override
  Future<String> createCollabLink(String token, String playlistId) async {
    final body = await _send(
        'POST', '/api/v1/playlists/${Uri.encodeComponent(playlistId)}/collab',
        token: token);
    return body['collabToken'] as String;
  }

  @override
  Future<void> revokeCollabLink(String token, String playlistId) async {
    await _send(
        'DELETE', '/api/v1/playlists/${Uri.encodeComponent(playlistId)}/collab',
        token: token, expectBody: false);
  }

  @override
  Future<Playlist> joinPlaylist(String token, String collabToken) async {
    final body = await _send(
        'POST', '/api/v1/collab/${Uri.encodeComponent(collabToken)}/join',
        token: token);
    return Playlist.fromJson(body);
  }

  @override
  Future<void> removePlaylistMember(
      String token, String playlistId, String memberId) async {
    await _send(
        'DELETE',
        '/api/v1/playlists/${Uri.encodeComponent(playlistId)}'
            '/members/${Uri.encodeComponent(memberId)}',
        token: token,
        expectBody: false);
  }

  @override
  Future<void> leavePlaylist(String token, String playlistId) async {
    await _send('DELETE',
        '/api/v1/playlists/${Uri.encodeComponent(playlistId)}/membership',
        token: token, expectBody: false);
  }

  @override
  Future<Playlist> getPlaylist(String token, String playlistId) async {
    final body =
        await _send('GET', '/api/v1/playlists/$playlistId', token: token);
    return Playlist.fromJson(body);
  }

  @override
  Future<Playlist> createPlaylist(String token, String name) async {
    final body = await _send('POST', '/api/v1/playlists',
        token: token, body: {'name': name});
    return Playlist.fromJson(body);
  }

  @override
  Future<Playlist> renamePlaylist(
      String token, String playlistId, String name) async {
    final body = await _send('PUT', '/api/v1/playlists/$playlistId',
        token: token, body: {'name': name});
    return Playlist.fromJson(body);
  }

  @override
  Future<Playlist> replacePlaylistTracks(
      String token, String playlistId, List<String> trackIds) async {
    final body = await _send('PUT', '/api/v1/playlists/$playlistId/tracks',
        token: token, body: {'trackIds': trackIds});
    return Playlist.fromJson(body);
  }

  @override
  Future<void> deletePlaylist(String token, String playlistId) async {
    await _send('DELETE', '/api/v1/playlists/$playlistId',
        token: token, expectBody: false);
  }

  @override
  Future<List<MessengerBot>> listBots(String token) async {
    final body = await _send('GET', '/api/v1/bots', token: token);
    return [
      for (final bot in body['bots'] as List<dynamic>)
        MessengerBot.fromJson(bot as Map<String, dynamic>),
    ];
  }

  @override
  Future<BotLinkCode> createBotLinkCode(String token) async {
    final body = await _send('POST', '/api/v1/bots/link-code', token: token);
    return BotLinkCode.fromJson(body);
  }

  @override
  Future<void> sendTrackToBot(
      String token, String provider, String trackId) async {
    await _send('POST', '/api/v1/bots/${Uri.encodeComponent(provider)}/send',
        token: token, body: {'trackId': trackId}, expectBody: false);
  }

  @override
  Future<LinkImport> importFromLink(String token, String url) async {
    final body = await _send('POST', '/api/v1/imports/link',
        body: {'url': url}, token: token);
    return LinkImport.fromJson(body);
  }

  @override
  Future<List<LinkImport>> listLinkImports(String token) async {
    final body = await _send('GET', '/api/v1/imports/link', token: token);
    return [
      for (final json in body['imports'] as List<dynamic>)
        LinkImport.fromJson(json as Map<String, dynamic>),
    ];
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? token,
    bool expectBody = true,
  }) async {
    final request = http.Request(method, baseUri.resolve(path));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    final response = await http.Response.fromStream(
      await _httpClient.send(request).timeout(_timeout),
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = decoded?['error'];
      throw ApiException(
        'Server returned HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
        code: code is String ? code : null,
      );
    }
    if (!expectBody) return const {};
    if (decoded == null) {
      throw const ApiException('Server returned an invalid response.');
    }
    return decoded;
  }

  static Map<String, dynamic>? _decode(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }
}
