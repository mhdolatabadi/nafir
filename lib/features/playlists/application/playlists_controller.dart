import 'package:flutter/foundation.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/playlists/data/playlist.dart';

enum PlaylistsStatus { loading, loaded, error }

class PlaylistsController extends ChangeNotifier {
  PlaylistsController({required PlaylistsApi api, required String? Function() token})
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
