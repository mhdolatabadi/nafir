import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/player/data/audio_cache.dart';
import 'package:nafir/features/player/data/crossfade.dart';

enum EngineState { idle, loading, buffering, ready, completed }

/// The part of an audio player the app uses, so it can be replaced in tests.
abstract interface class AudioEngine {
  Stream<Duration> get position;
  Stream<Duration?> get duration;
  Stream<bool> get playing;
  Stream<EngineState> get state;

  /// Playback failures after loading, for example an expired URL on seek.
  Stream<Object> get errors;

  /// The id of a [preload]ed track the engine moved on to by itself, at the
  /// end of the current one or as a crossfade began. Position and duration
  /// that follow belong to that track.
  Stream<String> get advanced;

  /// Whether tracks can overlap here; see [setCrossfade].
  bool get supportsCrossfade;

  /// Loads [track] as the current one, dropping anything preloaded.
  Future<void> load(Track track, Uri url, {Duration start = Duration.zero});

  /// Buffers [track] to follow the current one without a gap, or with the
  /// [setCrossfade] overlap. Replaces an earlier preload.
  Future<void> preload(Track track, Uri url);

  /// Forgets the preloaded track, so the current one ends by itself.
  Future<void> clearPreload();

  /// Starts playback without waiting for it to finish.
  void play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();

  /// Playback rate; 1 is normal. The pitch stays the same.
  Future<void> setSpeed(double speed);

  /// Overall loudness from 0 to 1, for example for a fade-out.
  Future<void> setVolume(double volume);

  /// How long a preloaded track overlaps the end of the current one. Only
  /// applies to later [preload]s, and only where [supportsCrossfade].
  Future<void> setCrossfade(Duration crossfade);

  Future<void> dispose();
}

/// One just_audio player and the tracks queued in it, by id.
class _Deck {
  _Deck() : player = AudioPlayer();

  final AudioPlayer player;
  ConcatenatingAudioSource? playlist;
  final ids = <String>[];

  int get index => player.currentIndex ?? 0;
}

/// Plays through just_audio. The current track and the preloaded next one
/// share a playlist, so the player moves between them without a gap; that
/// is sample-accurate on Android (ExoPlayer) and, in browsers, saves fetching
/// a new link before the next track starts.
///
/// A crossfade instead buffers the next track in a second player, which
/// starts quietly before the current track ends while the first fades out.
/// Browsers are left out: the fade steps run on JavaScript timers, which are
/// throttled in background tabs and on a locked phone, and a second media
/// element may not start there without a fresh tap. Fades would stutter or
/// the next track would not start, so crossfade is not offered on the web.
class JustAudioEngine implements AudioEngine {
  JustAudioEngine({AudioCache? cache, bool? supportsCrossfade})
      : _cache = cache ?? createAudioCache(),
        supportsCrossfade = supportsCrossfade ?? !kIsWeb {
    _active = _listen(_Deck());
  }

  final AudioCache _cache;

  @override
  final bool supportsCrossfade;

  late _Deck _active;

  /// The second player, created for the first crossfade.
  _Deck? _standby;

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _state = StreamController<EngineState>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  final _advanced = StreamController<String>.broadcast();

  String? _currentId;
  String? _nextId;
  double _speed = 1;
  double _volume = 1;
  Duration _crossfade = Duration.zero;

  Timer? _fade;
  _Deck? _fadingOut;
  Completer<void>? _fadeDone;

  /// Bumped by every load, stop and clear, so a preload that was still
  /// fetching its source when the queue moved on is dropped.
  int _generation = 0;

  _Deck _listen(_Deck deck) {
    final player = deck.player;
    player.positionStream.listen((value) {
      if (deck != _active) return;
      _position.add(value);
      _maybeCrossfade(value);
    });
    player.durationStream.listen((value) {
      if (deck == _active) _duration.add(value);
    });
    player.playingStream.listen((value) {
      if (deck == _active) _playing.add(value);
    });
    player.processingStateStream.listen((value) {
      if (deck == _active) _state.add(_engineState(value));
    });
    player.currentIndexStream.listen((index) => _onIndex(deck, index));
    player.playbackEventStream.listen((_) {}, onError: (Object error) {
      if (deck == _active) _errors.add(error);
    });
    return deck;
  }

  static EngineState _engineState(ProcessingState state) => switch (state) {
        ProcessingState.idle => EngineState.idle,
        ProcessingState.loading => EngineState.loading,
        ProcessingState.buffering => EngineState.buffering,
        ProcessingState.ready => EngineState.ready,
        ProcessingState.completed => EngineState.completed,
      };

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<Duration?> get duration => _duration.stream;

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Stream<EngineState> get state => _state.stream;

  @override
  Stream<Object> get errors => _errors.stream;

  @override
  Stream<String> get advanced => _advanced.stream;

  Future<AudioSource> _source(Track track, Uri url) async => track.isLocal
      ? AudioSource.uri(url, tag: track.id)
      : await _cache.sourceFor(track, url);

  @override
  Future<void> load(Track track, Uri url,
      {Duration start = Duration.zero}) async {
    _generation++;
    await _finishCrossfade();
    await _clearStandby();
    final source = await _source(track, url);
    final deck = _active;
    final playlist = ConcatenatingAudioSource(children: [source]);
    deck
      ..playlist = playlist
      ..ids.replaceRange(0, deck.ids.length, [track.id]);
    _currentId = track.id;
    _nextId = null;
    await deck.player.setVolume(_volume);
    await deck.player.setAudioSource(playlist, initialPosition: start);
  }

  @override
  Future<void> preload(Track track, Uri url) async {
    await clearPreload();
    final generation = _generation;
    // A short track can reach its preload point while it is still fading
    // in; the second player is free once that fade is over.
    await _fadeDone?.future;
    final source = await _source(track, url);
    if (generation != _generation) return;
    _nextId = track.id;
    if (supportsCrossfade && _crossfade > Duration.zero) {
      final deck = _standby ??= _listen(_Deck());
      final playlist = ConcatenatingAudioSource(children: [source]);
      deck
        ..playlist = playlist
        ..ids.replaceRange(0, deck.ids.length, [track.id]);
      await deck.player.setVolume(0);
      await deck.player.setSpeed(_speed);
      // Prepares and buffers it, paused, ready to fade in.
      await deck.player.setAudioSource(playlist);
    } else {
      final deck = _active;
      deck.ids.add(track.id);
      await deck.playlist?.add(source);
    }
  }

  @override
  Future<void> clearPreload() async {
    _generation++;
    _nextId = null;
    final deck = _active;
    final after = deck.index + 1;
    if (deck.ids.length > after) {
      deck.ids.removeRange(after, deck.ids.length);
      await deck.playlist?.removeRange(after, deck.playlist!.length);
    }
    await _clearStandby();
  }

  Future<void> _clearStandby() async {
    final standby = _standby;
    if (standby == null || standby == _fadingOut || standby.ids.isEmpty) {
      return;
    }
    standby.ids.clear();
    await standby.player.stop();
  }

  /// The active player reached the preloaded track by itself (gaplessly):
  /// report it, then drop the finished tracks before it.
  void _onIndex(_Deck deck, int? index) {
    if (deck != _active || index == null || index >= deck.ids.length) return;
    final id = deck.ids[index];
    if (id == _currentId || id != _nextId) return;
    _currentId = id;
    _nextId = null;
    _advanced.add(id);
    _duration.add(deck.player.duration);
    if (index > 0) {
      deck.ids.removeRange(0, index);
      unawaited(deck.playlist?.removeRange(0, index));
    }
  }

  void _maybeCrossfade(Duration position) {
    final standby = _standby;
    final duration = _active.player.duration;
    if (_fade != null ||
        standby == null ||
        standby.ids.isEmpty ||
        standby.ids.first != _nextId ||
        duration == null ||
        !_active.player.playing ||
        // Not buffered in time: the current track ends and the app moves on
        // as usual.
        standby.player.processingState != ProcessingState.ready) {
      return;
    }
    final overlap = effectiveCrossfade(_crossfade, duration, speed: _speed);
    if (!shouldStartCrossfade(
      position: position,
      duration: duration,
      crossfade: overlap,
      speed: _speed,
    )) {
      return;
    }
    _startCrossfade(standby, overlap);
  }

  void _startCrossfade(_Deck into, Duration overlap) {
    final out = _active;
    _active = into;
    _standby = out;
    _fadingOut = out;
    final id = into.ids.first;
    _currentId = id;
    _nextId = null;
    _fadeDone = Completer<void>();
    unawaited(into.player.play());
    _advanced.add(id);
    _duration.add(into.player.duration);
    _position.add(into.player.position);
    _playing.add(true);
    _state.add(_engineState(into.player.processingState));

    const step = Duration(milliseconds: 50);
    final steps = (overlap.inMilliseconds / step.inMilliseconds).ceil();
    var done = 0;
    _fade = Timer.periodic(step, (_) {
      done++;
      final (outGain, inGain) = crossfadeGains(done / steps);
      out.player.setVolume(_volume * outGain);
      into.player.setVolume(_volume * inGain);
      if (done >= steps) unawaited(_finishCrossfade());
    });
  }

  /// Ends a running crossfade at once: the outgoing track stops and the
  /// incoming one plays at full volume.
  Future<void> _finishCrossfade() async {
    final fade = _fade;
    final out = _fadingOut;
    if (fade == null || out == null) return;
    fade.cancel();
    _fade = null;
    _fadingOut = null;
    out.ids.clear();
    await _active.player.setVolume(_volume);
    await out.player.stop();
    _fadeDone?.complete();
    _fadeDone = null;
  }

  @override
  void play() => unawaited(_active.player.play());

  @override
  Future<void> pause() async {
    await _finishCrossfade();
    await _active.player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _finishCrossfade();
    await _active.player.seek(position);
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _finishCrossfade();
    await _clearStandby();
    _currentId = null;
    _nextId = null;
    await _active.player.stop();
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _active.player.setSpeed(speed);
    await _standby?.player.setSpeed(speed);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    // A running crossfade applies it on its next step.
    if (_fade == null) await _active.player.setVolume(_volume);
  }

  @override
  Future<void> setCrossfade(Duration crossfade) async {
    _crossfade = supportsCrossfade ? crossfade : Duration.zero;
  }

  @override
  Future<void> dispose() async {
    _fade?.cancel();
    _fadeDone?.complete();
    await _active.player.dispose();
    await _standby?.player.dispose();
    await Future.wait([
      _position.close(),
      _duration.close(),
      _playing.close(),
      _state.close(),
      _errors.close(),
      _advanced.close(),
    ]);
  }
}
