import 'package:flutter/foundation.dart';
import 'package:nafir/features/library/data/local_audio_library.dart';
import 'package:nafir/features/library/data/track.dart';

enum LocalAudioViewStatus {
  idle,
  loading,
  loaded,
  permissionDenied,
  error,
  unsupported,
}

class LocalAudioController extends ChangeNotifier {
  LocalAudioController(this._library);

  final LocalAudioLibrary _library;
  LocalAudioViewStatus _status = LocalAudioViewStatus.idle;
  List<Track> _tracks = const [];

  bool get supported => _library.supported;
  LocalAudioViewStatus get status => _status;
  List<Track> get tracks => _tracks;

  Future<void> load() async {
    if (!supported) {
      _status = LocalAudioViewStatus.unsupported;
      notifyListeners();
      return;
    }
    _status = LocalAudioViewStatus.loading;
    notifyListeners();
    try {
      final result = await _library.load();
      _tracks = result.tracks;
      _status = switch (result.status) {
        LocalAudioStatus.loaded => LocalAudioViewStatus.loaded,
        LocalAudioStatus.permissionDenied =>
          LocalAudioViewStatus.permissionDenied,
        LocalAudioStatus.unsupported => LocalAudioViewStatus.unsupported,
      };
    } catch (_) {
      _status = LocalAudioViewStatus.error;
    }
    notifyListeners();
  }
}
