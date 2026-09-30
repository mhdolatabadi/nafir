import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/library/data/track.dart';

enum LibraryStatus { loading, error, loaded }

/// Runs [callback] after [delay] and returns a function that cancels it.
typedef Schedule = void Function() Function(
    Duration delay, void Function() callback);

void Function() _timer(Duration delay, void Function() callback) =>
    Timer(delay, callback).cancel;

/// How long to wait between checks while bot imports are in progress: soon
/// at first, then less often, and not at all after about a quarter hour.
const importPollDelays = [
  Duration(seconds: 3),
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 20),
  Duration(seconds: 30),
  Duration(minutes: 1),
  Duration(minutes: 2),
  Duration(minutes: 5),
  Duration(minutes: 5),
];

/// The signed-in user's tracks, as the server lists them.
class LibraryController extends ChangeNotifier {
  LibraryController({
    required TracksApi api,
    required String? Function() token,
    Schedule? schedule,
  })  : _api = api,
        _token = token,
        _schedule = schedule ?? _timer;

  final TracksApi _api;
  final String? Function() _token;
  final Schedule _schedule;
  void Function()? _cancelPoll;
  int _pollStep = 0;
  int _importsInProgress = 0;

  LibraryStatus _status = LibraryStatus.loading;
  List<Track> _tracks = const [];
  int _usedBytes = 0;
  int _limitBytes = 0;
  int _generation = 0;
  final Set<String> _deletingTrackIds = {};
  final Set<String> _updatingTrackIds = {};

  LibraryStatus get status => _status;
  List<Track> get tracks => _tracks;
  int get usedBytes => _usedBytes;
  int get limitBytes => _limitBytes;

  /// Files sent to a Nafir bot that are still being added.
  int get importsInProgress => _importsInProgress;
  bool isDeleting(String trackId) => _deletingTrackIds.contains(trackId);
  bool isUpdating(String trackId) => _updatingTrackIds.contains(trackId);

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
      _followImports(library.importsInProgress);
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

  /// Updates the editable display metadata for an owned cloud track.
  Future<bool> updateTrackMetadata(
    String trackId, {
    required String title,
    String? artist,
    String? album,
  }) async {
    final token = _token();
    if (token == null || _updatingTrackIds.contains(trackId)) return false;
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) return false;
    String? clean(String? value) {
      final trimmed = value?.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    }

    _updatingTrackIds.add(trackId);
    notifyListeners();
    try {
      final updated = await _api.updateTrackMetadata(
        token,
        trackId,
        title: trimmedTitle,
        artist: clean(artist),
        album: clean(album),
      );
      _tracks = List.unmodifiable([
        for (final track in _tracks) track.id == updated.id ? updated : track,
      ]);
      return true;
    } catch (_) {
      return false;
    } finally {
      _updatingTrackIds.remove(trackId);
      notifyListeners();
    }
  }

  /// While bot imports are in progress, loads again after a growing delay
  /// so finished imports appear on their own.
  void _followImports(int inProgress) {
    final started = _importsInProgress == 0 && inProgress > 0;
    _importsInProgress = inProgress;
    _cancelPoll?.call();
    _cancelPoll = null;
    if (inProgress == 0) {
      _pollStep = 0;
      return;
    }
    if (started) _pollStep = 0;
    if (_pollStep >= importPollDelays.length) return;
    _cancelPoll = _schedule(importPollDelays[_pollStep++], () {
      _cancelPoll = null;
      load();
    });
  }

  @override
  void dispose() {
    _cancelPoll?.call();
    super.dispose();
  }

  /// Forgets the previous user's tracks, for example on logout.
  void clear() {
    _cancelPoll?.call();
    _cancelPoll = null;
    _importsInProgress = 0;
    _pollStep = 0;
    _generation++;
    _tracks = const [];
    _deletingTrackIds.clear();
    _updatingTrackIds.clear();
    _usedBytes = 0;
    _limitBytes = 0;
    _status = LibraryStatus.loading;
    notifyListeners();
  }
}
