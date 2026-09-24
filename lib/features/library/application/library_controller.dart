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
  int _generation = 0;

  LibraryStatus get status => _status;
  List<Track> get tracks => _tracks;

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
      final tracks = await _api.listTracks(token);
      if (generation != _generation) return false;
      _tracks = List.unmodifiable(tracks);
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

  /// Forgets the previous user's tracks, for example on logout.
  void clear() {
    _generation++;
    _tracks = const [];
    _status = LibraryStatus.loading;
    notifyListeners();
  }
}
