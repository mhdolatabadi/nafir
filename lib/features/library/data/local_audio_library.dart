import 'package:nafir/features/library/data/track.dart';

import 'local_audio_library_stub.dart'
    if (dart.library.io) 'local_audio_library_io.dart' as platform;

enum LocalAudioStatus { loaded, permissionDenied, unsupported }

class LocalAudioResult {
  const LocalAudioResult(this.status, [this.tracks = const []]);

  final LocalAudioStatus status;
  final List<Track> tracks;
}

abstract interface class LocalAudioLibrary {
  bool get supported;
  Future<LocalAudioResult> load();
}

LocalAudioLibrary createLocalAudioLibrary() =>
    platform.createLocalAudioLibrary();
