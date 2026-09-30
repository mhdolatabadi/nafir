import 'package:flutter/foundation.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/playlists/data/playlist.dart';

enum PlaylistsStatus { loading, loaded, error }

enum AddTrackResult { added, alreadyPresent, failure }

enum SaveSharedResult {
  saved,
  alreadyYours,
  noSpace,
  uploadsDisabled,
  gone,
  failed
}

/// A shared playlist link that is malformed, unknown or no longer shared.
class SharedPlaylistUnavailable implements Exception {
  const SharedPlaylistUnavailable();
}

class PlaylistsController extends ChangeNotifier {
  PlaylistsController(
      {required PlaylistsApi api, required String? Function() token})
      : _api = api,
        _token = token;

  final PlaylistsApi _api;
  final String? Function() _token;

  PlaylistsStatus status = PlaylistsStatus.loading;
  List<Playlist> playlists = const [];

  Future<bool> load() async {
    final token = _token();
    if (token == null) return false;
    status = PlaylistsStatus.loading;
    notifyListeners();
    try {
      playlists = await _api.listPlaylists(token);
      status = PlaylistsStatus.loaded;
      notifyListeners();
      return true;
    } catch (_) {
      status = PlaylistsStatus.error;
      notifyListeners();
      return false;
    }
  }

  Future<Playlist?> create(String name) async {
    final token = _token();
    if (token == null) return null;
    try {
      final playlist = await _api.createPlaylist(token, name);
      playlists = [playlist, ...playlists];
      status = PlaylistsStatus.loaded;
      notifyListeners();
      return playlist;
    } catch (_) {
      return null;
    }
  }

  /// Shares the playlist by link and returns its share token, or null.
  Future<String?> share(String id) async {
    final token = _token();
    if (token == null) return null;
    try {
      return await _api.sharePlaylist(token, id);
    } catch (_) {
      return null;
    }
  }

  /// Stops sharing; the old link stops working. Returns whether it worked.
  Future<bool> unshare(String id) async {
    final token = _token();
    if (token == null) return false;
    try {
      await _api.unsharePlaylist(token, id);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Opens a playlist someone shared. Throws [SharedPlaylistUnavailable]
  /// when the link is wrong or no longer shared, other errors when offline.
  Future<SharedPlaylist> openShared(String shareToken) async {
    final token = _token();
    if (token == null) throw const SharedPlaylistUnavailable();
    try {
      return await _api.getSharedPlaylist(token, shareToken);
    } on ApiException catch (e) {
      if (e.statusCode == 404) throw const SharedPlaylistUnavailable();
      rethrow;
    }
  }

  /// Copies a shared playlist and its tracks into this account.
  Future<SaveSharedResult> saveShared(String shareToken) async {
    final token = _token();
    if (token == null) return SaveSharedResult.failed;
    try {
      final saved = await _api.saveSharedPlaylist(token, shareToken);
      playlists = [saved, ...playlists];
      status = PlaylistsStatus.loaded;
      notifyListeners();
      return SaveSharedResult.saved;
    } on ApiException catch (e) {
      return switch (e.statusCode) {
        409 => SaveSharedResult.alreadyYours,
        413 => SaveSharedResult.noSpace,
        503 => SaveSharedResult.uploadsDisabled,
        404 => SaveSharedResult.gone,
        _ => SaveSharedResult.failed,
      };
    } catch (_) {
      return SaveSharedResult.failed;
    }
  }

  Future<Playlist?> loadPlaylist(String id) async {
    final token = _token();
    if (token == null) return null;
    try {
      return await _api.getPlaylist(token, id);
    } catch (_) {
      return null;
    }
  }

  Future<Playlist?> replaceTracks(String id, List<String> trackIds) async {
    final token = _token();
    if (token == null) return null;
    try {
      final playlist = await _api.replacePlaylistTracks(token, id, trackIds);
      await load();
      return playlist;
    } catch (_) {
      return null;
    }
  }

  Future<AddTrackResult> addTrack(String id, String trackId) async {
    final token = _token();
    if (token == null) return AddTrackResult.failure;
    try {
      final playlist = await _api.getPlaylist(token, id);
      final trackIds = playlist.tracks.map((track) => track.id).toList();
      if (trackIds.contains(trackId)) return AddTrackResult.alreadyPresent;
      final updated = await _api.replacePlaylistTracks(
        token,
        id,
        [...trackIds, trackId],
      );
      playlists = playlists
          .map((item) => item.id == id ? updated : item)
          .toList(growable: false);
      notifyListeners();
      return AddTrackResult.added;
    } catch (_) {
      return AddTrackResult.failure;
    }
  }

  Future<bool> rename(String id, String name) async {
    final token = _token();
    if (token == null) return false;
    try {
      await _api.renamePlaylist(token, id, name);
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> delete(String id) async {
    final token = _token();
    if (token == null) return false;
    try {
      await _api.deletePlaylist(token, id);
      playlists = playlists.where((playlist) => playlist.id != id).toList();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void clear() {
    playlists = const [];
    status = PlaylistsStatus.loading;
    notifyListeners();
  }
}
