import 'package:just_audio/just_audio.dart';
import 'package:nafir/features/library/data/track.dart';

import 'audio_cache_stub.dart' if (dart.library.io) 'audio_cache_io.dart'
    as platform;

/// Builds the audio source for a track. On devices with a file system, played
/// tracks are kept in a bounded, disposable cache; on the web the browser's
/// own HTTP cache is used.
abstract interface class AudioCache {
  Future<AudioSource> sourceFor(Track track, Uri url);

  /// Deletes everything cached.
  Future<void> clear();
}

AudioCache createAudioCache() => platform.createAudioCache();
