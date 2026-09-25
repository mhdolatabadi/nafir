import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/player/data/audio_cache.dart';

enum EngineState { idle, loading, buffering, ready, completed }

/// The part of an audio player the app uses, so it can be replaced in tests.
abstract interface class AudioEngine {
  Stream<Duration> get position;
  Stream<Duration?> get duration;
  Stream<bool> get playing;
  Stream<EngineState> get state;

  /// Playback failures after loading, for example an expired URL on seek.
  Stream<Object> get errors;

  Future<void> load(Track track, Uri url, {Duration start = Duration.zero});

  /// Starts playback without waiting for it to finish.
  void play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> dispose();
}

class JustAudioEngine implements AudioEngine {
  JustAudioEngine({AudioCache? cache}) : _cache = cache ?? createAudioCache() {
    _player.playbackEventStream.listen((_) {}, onError: (Object error) {
      _errors.add(error);
    });
  }

  final AudioPlayer _player = AudioPlayer();
  final AudioCache _cache;
  final _errors = StreamController<Object>.broadcast();

  @override
  Stream<Duration> get position => _player.positionStream;

  @override
  Stream<Duration?> get duration => _player.durationStream;

  @override
  Stream<bool> get playing => _player.playingStream;

  @override
  Stream<EngineState> get state =>
      _player.processingStateStream.map((state) => switch (state) {
            ProcessingState.idle => EngineState.idle,
            ProcessingState.loading => EngineState.loading,
            ProcessingState.buffering => EngineState.buffering,
            ProcessingState.ready => EngineState.ready,
            ProcessingState.completed => EngineState.completed,
          });

  @override
  Stream<Object> get errors => _errors.stream;

  @override
  Future<void> load(Track track, Uri url,
      {Duration start = Duration.zero}) async {
    final source = await _cache.sourceFor(track, url);
    await _player.setAudioSource(source, initialPosition: start);
  }

  @override
  void play() => unawaited(_player.play());

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() async {
    await _errors.close();
    await _player.dispose();
  }
}
