import 'package:flutter/foundation.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/library/data/track.dart';

enum LibraryStatus { loading, error, loaded }

/// The signed-in user's tracks, as the server lists them.
class LibraryController extends ChangeNotifier {
  LibraryController({
    required TracksApi api,
    required String? Function() token,
  })  : _api = api,
        _token = token;

  final TracksApi _api;
  final String? Function() _token;

  LibraryStatus _status = LibraryStatus.loading;
  List<Track> _tracks = const [];
  int _usedBytes = 0;
  int _limitBytes = 0;
  int _generation = 0;
  final Set<String> _deletingTrackIds = {};

  LibraryStatus get status => _status;
  List<Track> get tracks => _tracks;
  int get usedBytes => _usedBytes;
  int get limitBytes => _limitBytes;
  bool isDeleting(String trackId) => _deletingTrackIds.contains(trackId);

  /// Loads the list and reports whether it succeeded. Existing tracks stay on
  /// screen while refreshing; only a first load shows the loading state.
  Future<bool> load() async {
    final token = _token();
    if (token == null) return false;
    final generation = ++_generation;
    if (_status != LibraryStatus.loaded) {
      _status = LibraryStatus.loading;
      notifyListeners();
    }
    try {
      final library = await _api.listTracks(token);
      if (generation != _generation) return false;
      _tracks = List.unmodifiable(library.tracks);
      _usedBytes = library.usedBytes;
      _limitBytes = library.limitBytes;
      _status = LibraryStatus.loaded;
      return true;
    } catch (_) {
      if (generation != _generation) return false;
      if (_status != LibraryStatus.loaded) _status = LibraryStatus.error;
      return false;
    } finally {
      if (generation == _generation) notifyListeners();
    }
  }

  /// Deletes an owned cloud track and removes it from the visible library.
  /// The API also removes it from playlists through the database relation.
  Future<bool> deleteTrack(String trackId) async {
    final token = _token();
    if (token == null || _deletingTrackIds.contains(trackId)) return false;
    _deletingTrackIds.add(trackId);
    notifyListeners();
    try {
      final deleted = _tracks.where((track) => track.id == trackId).firstOrNull;
      await _api.deleteTrack(token, trackId);
      _generation++;
      _tracks = List.unmodifiable(
        _tracks.where((track) => track.id != trackId),
      );
      if (deleted != null) {
        final remaining = _usedBytes - deleted.sizeBytes;
        _usedBytes = remaining < 0 ? 0 : remaining;
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      _deletingTrackIds.remove(trackId);
      notifyListeners();
    }
  }

  /// Forgets the previous user's tracks, for example on logout.
  void clear() {
    _generation++;
    _tracks = const [];
    _usedBytes = 0;
    _limitBytes = 0;
    _status = LibraryStatus.loading;
    notifyListeners();
  }
}
